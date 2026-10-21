-- An online payment started and not paid no longer stops staff (444).
--
-- The owner's answer, 21 Oct 2026: "Staff can close it." The page says
-- "Online payment started, not paid" instead of "VIP payment waiting"; an
-- Owner or Manager can close the registration or the unpaid checkout; if
-- HitPay later reports money anyway, it lands in Website orders for a refund.
-- The owner's answer, 22 Oct 2026: only an Owner or Manager may close an
-- unpaid HitPay checkout, not an Admin.
--
--   G  Grants and md5s: the four changed functions keep their grants, have
--      444's AFTER md5s, and the three page functions check the caller first.
--   S  What the page is told: an open unpaid checkout is vip_checkout (its
--      order, when it opened, until when, for how many people) on the guest
--      and the To match entry;
--      an expired one, a paid one and a transfer are not.
--   C  Closing a registration: held under To match with an open checkout
--      (the production case): staff cannot, a Manager can, the checkout
--      closes with it (dismissed, "Checkout closed: <reason>", audited), the
--      person's VIP state is 'none' and their guest record cancelled; an
--      expired checkout closes with it too; a group checkout closes for both
--      (the other may start a new one); money taken or a transfer sent still
--      stops it with 436's words; a Manager without the store's access is
--      refused.
--   W  Website orders: a Manager closes an open unpaid checkout with a reason
--      (too short refused; audited); staff and an Admin cannot (22 Oct 2026);
--      one with a payment on it (any of HitPay's ids, a paid time, an amount)
--      is refused, as is a HitPay payment (436's words); a closed checkout is
--      not restored; an Admin still dismisses and restores a transfer (436),
--      and a transfer's dismiss reason cannot pose as a closed checkout.
--   L  HitPay reports a payment for a closed checkout anyway: kept for a
--      Manager (needs review, the reason first, no invoice, the answer says
--      so); the same notice again answers the same; for a closed person
--      "Create invoices" still waits (436) and it is closed as refunded; for
--      someone still registered a Manager creates its invoices by hand; a
--      test key's dry run says a live key would have kept it (the close
--      reason cleared).
--   N  Nothing else: an open checkout that is paid is invoiced as before; the
--      website's VIP states are still 'none' / 'pending' / 'paid' /
--      'refunded'.
--   M  444 twice changes nothing; its self-test leaves no row (when this file
--      installs it).
--
-- Disposable local database only; everything is rolled back. Every name and
-- email is invented (@example.com); phones are ACMA's fictional range (+61 2
-- 5550 ....). Run it on a copy of production as it is (436 and 439 applied):
-- it applies 444 twice, or run it with -v skip_install=1 where 444 is already
-- installed. Every check runs, then the file fails if any did.
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
create temp table r444 as select pg_temp.row_counts() as before;
\ir ../../../supabase/444_event_website_unpaid_checkout_can_be_closed.sql
create temp table m444 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
alter table r444 add column after1 jsonb;
update r444 set after1 = pg_temp.row_counts();
\ir ../../../supabase/444_event_website_unpaid_checkout_can_be_closed.sql
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
$$ select 'ht444-' || lower(tag) || '-' || lower(pg_temp.tx('sfx')) || '@example.com' $$;
create function pg_temp.bid(prefix text, tag text) returns text language sql as
$$ select prefix || '-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || prefix || tag), 1, 8)) $$;
create function pg_temp.person(pos int, first text, last text, phone text, email text)
returns jsonb language sql as
$$ select jsonb_build_object('position', pos, 'first_name', first, 'last_name', last, 'phone', phone, 'email', email,
            'days', jsonb_build_array(pg_temp.d(7)), 'vip', false) $$;
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
-- One form (people: a jsonb array); each person's id and token kept under <tag><position>.
create function pg_temp.reg(tag text, people jsonb, kind text default 'live') returns jsonb language plpgsql as $$
declare v jsonb; x jsonb;
begin
  v := pg_temp.call(kind, 'register', jsonb_build_object('registration', jsonb_build_object(
         'registration_id', pg_temp.bid('REG', tag), 'submitted_at', now(), 'referral_code', null, 'people', people)));
  for x in select y from jsonb_array_elements(v->'people') y loop
    perform pg_temp.putx(tag || (x->>'position'), (x->>'person_id')::uuid);
    perform pg_temp.put('tok:' || tag || (x->>'position'), x->>'upgrade_token');
  end loop;
  return v;
end $$;
create function pg_temp.pp(tag text) returns public.event_registration_people language sql as
$$ select * from public.event_registration_people where id = pg_temp.fx(tag) $$;
create function pg_temp.toks(tags text[]) returns jsonb language sql as
$$ select jsonb_agg(pg_temp.tx('tok:' || t) order by n) from unnest(tags) with ordinality u(t, n) $$;
-- A HitPay checkout opened (minutes ago) for the people, by their tags.
create function pg_temp.checkout(kind text, tag text, people text[], ago interval default interval '3 minutes') returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_checkout', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', pg_temp.toks(people),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null),
     'livemode', kind = 'live', 'checkout_opened_at', now() - ago))) $$;
-- HitPay's payment for that checkout (the same request id answers the same).
create function pg_temp.paid(kind text, tag text, people text[], cents int default 7200, req uuid default gen_random_uuid()) returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_paid', jsonb_build_object('payment', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'provider', 'hitpay',
     'payment_request_id', md5('rq' || tag || pg_temp.tx('sfx'))::uuid, 'payment_id', md5('py' || tag || pg_temp.tx('sfx'))::uuid,
     'amount_cents', cents, 'currency', 'SGD', 'livemode', kind = 'live', 'paid_at', now() - interval '1 minute',
     'upgrade_tokens', pg_temp.toks(people),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null))), req) $$;
create function pg_temp.vorder(tag text) returns public.event_vip_orders language sql as
$$ select * from public.event_vip_orders where order_id = pg_temp.bid('VIP', tag) $$;
create function pg_temp.vinvoices(tag text) returns setof public.invoices language sql as
$$ select i.* from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
     join public.invoices i on i.id = op.invoice_id where o.order_id = pg_temp.bid('VIP', tag) $$;
-- What the Event page reads (as the Owner): a person's To match entry, and their guest row.
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
create function pg_temp.guest(tag text) returns jsonb language sql as
$$ select g from jsonb_array_elements(pg_temp.extras()->'guests') g
    where (g->>'person_id')::uuid = pg_temp.fx(tag) and (g->>'guest_id')::uuid = (pg_temp.pp(tag)).free_guest_id $$;
create function pg_temp.audits(tag text, act text) returns bigint language sql as
$$ select count(*) from audit_logs l where l.action = act and l.record_id = (pg_temp.vorder(tag)).id $$;
create function pg_temp.cust(name text, phone text, email text) returns uuid language sql as
$$ insert into customers(full_name, phone, email) values (name, phone, email) returning id $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; st2 uuid; ev uuid; src uuid; pm uuid; v1 uuid; v2 uuid;
begin
  insert into tx values ('sfx', sfx), ('phbase', (floor(random() * 9000))::int::text);
  foreach k in array array['owner', 'acting', 'manager', 'manager2', 'admin', 'staff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'ht444-' || k || '-' || lower(sfx) || '@example.com');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'HT444 ' || initcap(k) || ' ' || sfx, 'ht444-' || k || '-' || lower(sfx) || '@example.com',
            case k when 'owner' then 'owner' when 'acting' then 'owner' when 'admin' then 'admin' when 'staff' then 'staff'
                   else 'manager' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('HT444 Van ' || sfx, 'HT444V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('HT444 Shop ' || sfx, 'HT444S' || sfx, 'SG') returning id into st2;
  insert into fx values ('van', st), ('shop', st2);
  insert into user_store_assignments(user_id, store_id)
  values (pg_temp.fx('manager'), st), (pg_temp.fx('admin'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('manager2'), st2);
  ev := public.event_save(jsonb_build_object('name', 'HT444 Health Seminar ' || sfx,
    'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st, st2),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev', ev), ('vip', (select id from public.event_ticket_options where event_id = ev));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('HT444 Event ' || sfx, true, true, 9999) returning id into src;
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('HT444 $72 discount Voucher', 'HT444SAVE72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('HT444 3-in-1 Vouchers', 'HT444-3IN1' || sfx, 'normal', 'unlimited', 216, true) returning id into v2;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v1, st, 72, true), (v2, st, 216, true);
  perform public.event_web_settings_save(ev, jsonb_build_object('code', 'HT444-' || sfx, 'mode', 'live', 'venue', null,
     'store_id', st, 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
     'vip_voucher_ids', jsonb_build_array(v1, v2), 'gift_product_ids', '[]'::jsonb,
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', src,
     'source_details', 'Health Seminar (website)', 'sync_url', 'https://healthtalk.example.com/api/app/sync'));
  insert into tx values ('code', 'HT444-' || sfx);
  -- Someone whose phone the held people below share.
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

-- ═════ G Grants and md5s ═════
select pg_temp.check((select bool_and(not has_function_privilege('anon', x.f, 'execute')
                                      and has_function_privilege('authenticated', x.f, 'execute') = x.page
                                      and has_function_privilege('service_role', x.f, 'execute'))
                        from (values ('public.event_registration_close(uuid,text)', true),
                                     ('public.event_vip_order_dismiss(uuid,text,boolean)', true),
                                     ('public.event_web_vip_paid(uuid,jsonb)', false),
                                     ('public.event_web_guest_extras(uuid)', true)) x(f, page)),
  'G1 the four changed functions keep their grants (the three page functions signed-in staff''s, vip_paid the service role''s)');
select pg_temp.check((select bool_and(md5(pg_get_functiondef(x.f::regprocedure)) = x.m)
                        from (values ('public.event_registration_close(uuid,text)', 'ae3df7387a2057281778258ead3aa4df'),
                                     ('public.event_vip_order_dismiss(uuid,text,boolean)', 'd1b16a09f2376591688feb42585c8146'),
                                     ('public.event_web_vip_paid(uuid,jsonb)', '1e1e48047b36af39495ef767a37237c2'),
                                     ('public.event_web_guest_extras(uuid)', '369914bd689e9aa1d34e8e2d887b1d43')) x(f, m)),
  'G2 the four functions have 444''s AFTER md5s');
select pg_temp.check((select bool_and(pg_get_functiondef(x.f::regprocedure) ~ E'\nbegin\n  perform public\\.require_active_staff\\(')
                        from (values ('public.event_registration_close(uuid,text)'), ('public.event_vip_order_dismiss(uuid,text,boolean)'),
                                     ('public.event_web_guest_extras(uuid)')) x(f)),
  'G3 the three page functions still call require_active_staff first');
select pg_temp.check(to_regprocedure('public.event_vip_order_close_checkout(uuid,text)') is null
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
           and (p.proname like 'event\_web\_%' or p.proname like 'event\_vip\_%' or p.proname like 'event\_registration\_%')
           and has_function_privilege('authenticated', p.oid, 'execute')) = 17,
  'G4 no new function: the page reaches the same 17 event_web / event_vip / event_registration functions as before');

-- ═════ S and C: held under To match with an open checkout (the production case) ═════
-- One form: Ann on the holder's phone under another name (held), Ben on a new phone (a new customer).
select pg_temp.reg('c', jsonb_build_array(pg_temp.person(1, 'Ann', 'Heldback', pg_temp.ph(1), pg_temp.mail('ann')),
                                         pg_temp.person(2, 'Ben', 'Newone', pg_temp.ph(2), pg_temp.mail('ben'))));
select pg_temp.put('c_co', pg_temp.checkout('live', 'c1v', array['c1'])::text);
select pg_temp.put('c_co_again', pg_temp.checkout('live', 'c1w', array['c1'])::text);
select pg_temp.check((pg_temp.pp('c1')).match = 'held' and (pg_temp.pp('c1')).hold_reason = 'phone_in_use'
    and (pg_temp.tx('c_co')::jsonb)->>'status' = 'ok'
    and (pg_temp.vorder('c1v')).status = 'pending' and (pg_temp.vorder('c1v')).hitpay_payment_request_id is null
    and (pg_temp.vorder('c1v')).expires_at = (pg_temp.vorder('c1v')).checkout_opened_at + interval '70 minutes'
    and public.event_web_person_vip_state(pg_temp.fx('c1')) = 'pending'
    and (pg_temp.tx('c_co_again')::jsonb) @> '{"status": "refused", "reason": "payment_waiting"}'::jsonb,
  'C0 (the bug) held under To match, a checkout opened and left: pending for 70 minutes, a second checkout refused: ' || pg_temp.tx('c_co'));
select pg_temp.check(pg_temp.hold('c1')->'vip_checkout' = jsonb_build_object('order_id', pg_temp.bid('VIP', 'c1v'),
                       'opened_at', (pg_temp.vorder('c1v')).checkout_opened_at, 'expires_at', (pg_temp.vorder('c1v')).expires_at,
                       'people', 1)
    and pg_temp.guest('c1')->'vip_checkout'->>'order_id' = pg_temp.bid('VIP', 'c1v')
    and (pg_temp.hold('c1')->>'vip_payment')::boolean = false and pg_temp.guest('c1')->'vip_waiting' = 'null'::jsonb
    and pg_temp.guest('c1')->>'vip' = 'pending'
    and pg_temp.guest('c2')->'vip_checkout' = 'null'::jsonb,
  'S1 the page is told: an online payment started and not paid (order, opened, until, for how many), on To match and the guest; not a payment waiting; none for Ben: '
  || coalesce(pg_temp.hold('c1')->>'vip_checkout', 'none'));
select pg_temp.as_user('staff');
select pg_temp.put('c_staff', pg_temp.errcode(format('select public.event_registration_close(%L, %L)', pg_temp.fx('c1'), 'Not coming')));
select pg_temp.as_user('admin');
select pg_temp.put('c_admin', pg_temp.errcode(format('select public.event_registration_close(%L, %L)', pg_temp.fx('c1'), 'Not coming')));
select pg_temp.as_user('manager2');
select pg_temp.put('c_m2', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('c1'), 'Not coming')));
select pg_temp.as_user('manager');
select pg_temp.put('c_close', public.event_registration_close(pg_temp.fx('c1'), 'Pressed back, not coming')::text);
select pg_temp.check(pg_temp.tx('c_staff') = '42501' and pg_temp.tx('c_admin') = '42501'
    and pg_temp.tx('c_m2') = 'You do not have access to this event''s store',
  'C1 staff and an Admin cannot close a registration; a Manager without the event store''s access neither');
select pg_temp.check((pg_temp.tx('c_close')::jsonb) = jsonb_build_object('ok', true, 'checkouts_closed',
                       jsonb_build_array(jsonb_build_object('order_id', pg_temp.bid('VIP', 'c1v'), 'people', 1, 'open', true)))
    and (pg_temp.pp('c1')).match = 'closed'
    and ((pg_temp.vorder('c1v')).status, (pg_temp.vorder('c1v')).status_before_dismiss, (pg_temp.vorder('c1v')).review_reason)
        = ('dismissed'::text, 'pending'::text, 'Checkout closed: Pressed back, not coming'::text)
    and (pg_temp.vorder('c1v')).updated_by = pg_temp.fx('manager')
    and public.event_web_person_vip_state(pg_temp.fx('c1')) = 'none'
    and (select g.status from event_guests g where g.id = (pg_temp.pp('c1')).free_guest_id) = 'cancelled'
    and pg_temp.hold('c1') is null and pg_temp.guest('c1')->'vip_checkout' = 'null'::jsonb
    and pg_temp.audits('c1v', 'event_vip_checkout_closed') = 1
    and (select l.new_data->'checkouts_closed'->0->>'order_id' from audit_logs l
          where l.record_id = pg_temp.fx('c1') and l.action = 'event_registration_closed') = pg_temp.bid('VIP', 'c1v'),
  'C2 a Manager closes it: the checkout closes with it (dismissed, "Checkout closed: <reason>", audited), VIP none, off the guest list and To match: '
  || pg_temp.tx('c_close'));
select pg_temp.check((pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tx('tok:c1')))->'person'->>'reason') = 'cancelled',
  'C3 the website says the closed person cannot upgrade (cancelled)');

-- An expired checkout closes with the registration too; a group checkout closes for both, the other starts a new one.
select pg_temp.reg('e', jsonb_build_array(pg_temp.person(1, 'Eve', 'Expired', pg_temp.ph(1), pg_temp.mail('eve'))));
select pg_temp.checkout('live', 'e1v', array['e1'], interval '80 minutes');
select pg_temp.reg('g', jsonb_build_array(pg_temp.person(1, 'Gail', 'Group', pg_temp.ph(1), pg_temp.mail('gail')),
                                         pg_temp.person(2, 'Gus', 'Group', pg_temp.ph(3), pg_temp.mail('gus'))));
select pg_temp.checkout('live', 'g12v', array['g1', 'g2']);
select pg_temp.check((pg_temp.vorder('e1v')).status = 'pending' and (pg_temp.vorder('e1v')).expires_at < now()
    and pg_temp.hold('e1')->'vip_checkout' = 'null'::jsonb and (pg_temp.hold('e1')->>'vip_waiting')::boolean
    and (pg_temp.vorder('g12v')).quantity = 2 and pg_temp.guest('g2')->'vip_checkout'->>'order_id' = pg_temp.bid('VIP', 'g12v')
    and pg_temp.guest('g2')->'vip_checkout'->>'people' = '2' and pg_temp.hold('g1')->'vip_checkout'->>'people' = '2',
  'S2 an expired checkout is not shown as open (436''s vip_waiting still counts it); a group checkout shows on each person, for 2 people');
select pg_temp.as_user('owner');
select pg_temp.put('e_close', public.event_registration_close(pg_temp.fx('e1'), 'Duplicate form')::text);
select pg_temp.put('g_close', public.event_registration_close(pg_temp.fx('g1'), 'Duplicate form')::text);
select pg_temp.put('g_new', pg_temp.checkout('live', 'g2v', array['g2'])::text);
select pg_temp.check((pg_temp.tx('e_close')::jsonb)->'checkouts_closed' = jsonb_build_array(jsonb_build_object(
                       'order_id', pg_temp.bid('VIP', 'e1v'), 'people', 1, 'open', false))
    and (pg_temp.vorder('e1v')).status = 'dismissed'
    and (pg_temp.tx('g_close')::jsonb)->'checkouts_closed'->0->>'people' = '2'
    and (pg_temp.vorder('g12v')).status = 'dismissed' and (pg_temp.pp('g2')).match <> 'closed'
    and public.event_web_person_vip_state(pg_temp.fx('g2')) = 'pending'
    and (pg_temp.tx('g_new')::jsonb)->>'status' = 'ok',
  'C4 an expired checkout closes with the registration; a group checkout closes for both, and the other person starts a new one');

-- Money taken, or a transfer sent, still stops it (436's words).
select pg_temp.reg('m', jsonb_build_array(pg_temp.person(1, 'Mia', 'Moneytaken', pg_temp.ph(1), pg_temp.mail('mia')),
                                         pg_temp.person(2, 'Max', 'Transfer', pg_temp.ph(1), pg_temp.mail('max'))));
select pg_temp.checkout('live', 'm1v', array['m1']);
select pg_temp.put('m1_paid', pg_temp.paid('live', 'm1v', array['m1'])::text);
select pg_temp.call('live', 'vip_transfer', jsonb_build_object('order', jsonb_build_object(
  'order_id', pg_temp.bid('VIP', 'm2t'), 'upgrade_tokens', pg_temp.toks(array['m2']),
  'payer', jsonb_build_object('name', 'Max Transfer', 'email', pg_temp.mail('max'), 'phone', null),
  'method', 'paynow', 'reference', 'PN-444', 'paid_on', public.sg_today(), 'amount_cents', 7200, 'submitted_at', now())));
select pg_temp.as_user('manager');
select pg_temp.put('m1_close', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('m1'), 'Duplicate')));
select pg_temp.put('m2_close', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('m2'), 'Duplicate')));
select pg_temp.check((pg_temp.vorder('m1v')).status = 'needs_review' and (pg_temp.vorder('m2t')).status in ('recorded', 'needs_review')
    and pg_temp.tx('m1_close') = 'A VIP payment for Mia Moneytaken is waiting: deal with it on Website orders first.'
    and pg_temp.tx('m2_close') = 'A VIP payment for Max Transfer is waiting: deal with it on Website orders first.'
    and (pg_temp.pp('m1')).match = 'held' and (pg_temp.pp('m2')).match = 'held'
    and pg_temp.hold('m1')->'vip_checkout' = 'null'::jsonb and (pg_temp.hold('m1')->>'vip_payment')::boolean,
  'C5 a HitPay payment taken (held: it waits for the match) or a transfer sent still stops the close, with 436''s words: '
  || pg_temp.tx('m1_close'));

-- ═════ W Website orders: Close unpaid checkout ═════
select pg_temp.reg('w', jsonb_build_array(pg_temp.person(1, 'Wanda', 'Webclose', pg_temp.ph(4), pg_temp.mail('wanda')),
                                         pg_temp.person(2, 'Walt', 'Withpay', pg_temp.ph(5), pg_temp.mail('walt'))));
select pg_temp.checkout('live', 'w1v', array['w1']);
select pg_temp.checkout('live', 'w2v', array['w2']);
-- Walt's: HitPay's payment id written on it while still pending (each part of a payment refuses on its own).
update event_vip_orders set hitpay_payment_id = 'pay-444' where order_id = pg_temp.bid('VIP', 'w2v');
select pg_temp.as_user('staff');
select pg_temp.put('w_staff', pg_temp.errcode(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('w1v')).id, 'Never paid')));
select pg_temp.as_user('manager2');
select pg_temp.put('w_m2', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('w1v')).id, 'Never paid')));
-- An Admin cannot close one (the owner, 22 Oct 2026: an Owner or Manager only).
select pg_temp.as_user('admin');
select pg_temp.put('w_admin', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('w1v')).id, 'Never paid')));
select pg_temp.put('w_admin_code', pg_temp.errcode(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('w1v')).id, 'Never paid')));
select pg_temp.put('w_admin_after', (pg_temp.vorder('w1v')).status || ' ' || pg_temp.audits('w1v', 'event_vip_checkout_closed'));
select pg_temp.as_user('manager');
select pg_temp.put('w_short', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('w1v')).id, 'no')));
select pg_temp.put('w_pay', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('w2v')).id, 'Never paid')));
do $$ declare r text; f text; begin
  foreach f in array array['hitpay_payment_request_id = ''req-444''', 'paid_at = now()', 'amount_paid_cents = 7200'] loop
    execute format('update event_vip_orders set hitpay_payment_id = null, hitpay_payment_request_id = null, paid_at = null, '
                   || 'amount_paid_cents = null where order_id = %L', pg_temp.bid('VIP', 'w2v'));
    execute format('update event_vip_orders set %s where order_id = %L', f, pg_temp.bid('VIP', 'w2v'));
    r := pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('w2v')).id, 'Never paid'));
    perform pg_temp.put('w_pay:' || split_part(f, ' ', 1), r);
  end loop;
end $$;
select pg_temp.put('w_paid_hp', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('m1v')).id, 'Never paid')));
select pg_temp.put('w1', public.event_vip_order_dismiss((pg_temp.vorder('w1v')).id, '  Went back without paying ', true)::text);
select pg_temp.put('w_again', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('w1v')).id, 'Again')));
select pg_temp.put('w_restore', pg_temp.err(format('select public.event_vip_order_dismiss(%L, null, false)', (pg_temp.vorder('w1v')).id)));
-- An Admin keeps what 436 gave them on Website orders: dismissing and restoring a transfer.
select pg_temp.as_user('admin');
select pg_temp.put('w_fake', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('m2t')).id, 'Checkout closed: a transfer')));
select pg_temp.put('w_tr_before', (pg_temp.vorder('m2t')).status || ' ' || coalesce((pg_temp.vorder('m2t')).review_reason, '-'));
select pg_temp.put('w_tr_dismiss', public.event_vip_order_dismiss((pg_temp.vorder('m2t')).id, ' Sent twice by mistake ', true)::text);
select pg_temp.put('w_tr_dismissed', (pg_temp.vorder('m2t')).status || ' ' || (pg_temp.vorder('m2t')).review_reason);
select pg_temp.put('w_tr_restore', public.event_vip_order_dismiss((pg_temp.vorder('m2t')).id, null, false)::text);
select pg_temp.check(pg_temp.tx('w_staff') = '42501' and pg_temp.tx('w_m2') = 'You do not have access to this event''s store'
    and pg_temp.tx('w_admin') = 'Only an Owner or Manager can close an unpaid checkout.' and pg_temp.tx('w_admin_code') = '42501'
    and pg_temp.tx('w_admin_after') = 'pending 0'
    and pg_temp.tx('w_short') = 'Give a reason (at least 3 characters)',
  'W1 staff and an Admin cannot close a checkout (the owner, 22 Oct 2026); a Manager without the store''s access neither; a reason is needed: '
  || pg_temp.tx('w_admin'));
select pg_temp.check(pg_temp.tx('w_pay') = 'HitPay reported a payment for this order: create its invoices, or close it as refunded.'
    and pg_temp.tx('w_pay:hitpay_payment_request_id') = pg_temp.tx('w_pay') and pg_temp.tx('w_pay:paid_at') = pg_temp.tx('w_pay')
    and pg_temp.tx('w_pay:amount_paid_cents') = pg_temp.tx('w_pay')
    and (pg_temp.vorder('w2v')).status = 'pending'
    and pg_temp.tx('w_paid_hp') = 'A HitPay payment took money: create its invoices, or close it as refunded.',
  'W2 a checkout with any part of a payment on it (payment id, request id, paid time, amount) is refused; a HitPay payment as 436');
select pg_temp.check((pg_temp.tx('w1')::jsonb) = '{"ok": true, "checkout_closed": true}'::jsonb
    and ((pg_temp.vorder('w1v')).status, (pg_temp.vorder('w1v')).status_before_dismiss, (pg_temp.vorder('w1v')).review_reason)
        = ('dismissed'::text, 'pending'::text, 'Checkout closed: Went back without paying'::text)
    and (pg_temp.vorder('w1v')).updated_by = pg_temp.fx('manager')
    and pg_temp.audits('w1v', 'event_vip_checkout_closed') = 1
    and (select l.reason from audit_logs l where l.record_id = (pg_temp.vorder('w1v')).id and l.action = 'event_vip_checkout_closed')
        = 'Went back without paying'
    and public.event_web_person_vip_state(pg_temp.fx('w1')) = 'none' and (pg_temp.pp('w1')).match <> 'closed'
    and pg_temp.tx('w_again') = 'This checkout is already closed.'
    and pg_temp.tx('w_restore') = 'A closed checkout is not reopened: the person can start a new one on the website.'
    and (pg_temp.vorder('w1v')).status = 'dismissed',
  'W3 a Manager closes an open unpaid checkout (audited, the person stays registered, VIP none); it is not restored: '
  || pg_temp.tx('w_again'));
select pg_temp.check(pg_temp.tx('w_fake') = 'Give the reason in your own words'
    and (pg_temp.tx('w_tr_dismiss')::jsonb) = '{"ok": true}'::jsonb
    and pg_temp.tx('w_tr_dismissed') = 'dismissed Sent twice by mistake'
    and (pg_temp.tx('w_tr_restore')::jsonb) = '{"ok": true}'::jsonb
    and (pg_temp.vorder('m2t')).status || ' ' || coalesce((pg_temp.vorder('m2t')).review_reason, '-') = pg_temp.tx('w_tr_before')
    and (pg_temp.vorder('m2t')).updated_by = pg_temp.fx('admin')
    and pg_temp.audits('m2t', 'event_vip_order_dismissed') = 1 and pg_temp.audits('m2t', 'event_vip_order_restored') = 1,
  'W4 an Admin still dismisses and restores a transfer (436); a transfer''s reason cannot pose as a closed checkout: '
  || pg_temp.tx('w_tr_dismissed'));

-- ═════ L HitPay reports a payment for a closed checkout anyway ═════
select pg_temp.put('l_rq', gen_random_uuid()::text);
select pg_temp.put('l_c1', pg_temp.paid('live', 'c1v', array['c1'], 7200, pg_temp.tx('l_rq')::uuid)::text);
select pg_temp.put('l_c1_again', pg_temp.paid('live', 'c1v', array['c1'], 7200, pg_temp.tx('l_rq')::uuid)::text);
select pg_temp.put('l_w1', pg_temp.paid('live', 'w1v', array['w1'])::text);
select pg_temp.check((pg_temp.tx('l_c1')::jsonb) @> '{"ok": true, "status": "needs_review"}'::jsonb
    and (pg_temp.tx('l_c1')::jsonb)->>'review_reason' = 'The checkout was closed before HitPay reported this payment: refund it in HitPay, '
        || 'or create its invoices by hand if they should still have VIP. Person 1 on this order is no longer registered (cancelled or closed)'
    and pg_temp.tx('l_c1_again') = pg_temp.tx('l_c1')
    and (pg_temp.vorder('c1v')).status = 'needs_review' and (pg_temp.vorder('c1v')).status_before_dismiss is null
    and (pg_temp.vorder('c1v')).amount_paid_cents = 7200 and (pg_temp.vorder('c1v')).hitpay_payment_id is not null
    and not exists (select 1 from pg_temp.vinvoices('c1v'))
    and (pg_temp.tx('l_w1')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('l_w1')::jsonb)->>'review_reason' = 'The checkout was closed before HitPay reported this payment: refund it in HitPay, '
        || 'or create its invoices by hand if they should still have VIP'
    and not exists (select 1 from pg_temp.vinvoices('w1v')),
  'L1 a payment for a closed checkout waits for a Manager (needs review, the reason first), nothing invoiced, no error; the same notice again answers the same: '
  || pg_temp.tx('l_c1'));
select pg_temp.as_user('manager');
select pg_temp.put('l_inv_c1', public.event_vip_order_invoice((pg_temp.vorder('c1v')).id)::text);
select pg_temp.put('l_ref_c1', pg_temp.err(format('select public.event_vip_order_close_refunded(%L, %L, true)', (pg_temp.vorder('c1v')).id, 'Refunded in HitPay')));
select pg_temp.put('l_inv_w1', public.event_vip_order_invoice((pg_temp.vorder('w1v')).id)::text);
select pg_temp.check((pg_temp.tx('l_inv_c1')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('l_inv_c1')::jsonb)->>'review_reason' = 'Person 1 on this order was closed by staff'
    and pg_temp.tx('l_ref_c1') = 'ok'
    and ((pg_temp.vorder('c1v')).status, (pg_temp.vorder('c1v')).review_reason) = ('dismissed'::text, 'Refunded outside the app: Refunded in HitPay'::text)
    and (pg_temp.tx('l_inv_w1')::jsonb)->>'status' = 'invoiced' and (select count(*) from pg_temp.vinvoices('w1v')) = 1
    and (select i.status::text from pg_temp.vinvoices('w1v') i) = 'paid'
    and public.event_web_person_vip_state(pg_temp.fx('w1')) = 'paid',
  'L2 a closed person''s payment is never invoiced (436) and is closed as refunded; someone still registered is invoiced by hand: ' || pg_temp.tx('l_inv_w1'));
-- A test key's checkout closed, then HitPay's sandbox pays: the dry run says a live key would have kept it.
select pg_temp.reg('t', jsonb_build_array(pg_temp.person(1, 'Tess', 'Testkey', pg_temp.ph(6), pg_temp.mail('tess'))), 'test');
select pg_temp.checkout('test', 't1v', array['t1']);
select pg_temp.as_user('manager');
select pg_temp.put('t_close', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('t1v')).id, 'Testing the back button')));
select pg_temp.put('t_paid', pg_temp.paid('test', 't1v', array['t1'])::text);
select pg_temp.check(pg_temp.tx('t_close') = 'ok' and (pg_temp.tx('t_paid')::jsonb) @> '{"test": true, "status": "test"}'::jsonb
    and (pg_temp.vorder('t1v')).test_would = 'needs_review'
    and (pg_temp.vorder('t1v')).test_note like 'A live key would have kept this for a Manager: the checkout was closed before HitPay reported%'
    and (pg_temp.vorder('t1v')).review_reason is null and (pg_temp.vorder('t1v')).status_before_dismiss is null,
  'L3 the test key: a closed checkout''s sandbox payment is a test whose note says a live key would have kept it for a Manager (staff''s close reason gives way): '
  || pg_temp.tx('t_paid'));

-- ═════ N Nothing else ═════
select pg_temp.reg('n', jsonb_build_array(pg_temp.person(1, 'Nina', 'Paysnow', pg_temp.ph(7), pg_temp.mail('nina'))));
select pg_temp.checkout('live', 'n1v', array['n1']);
select pg_temp.put('n_paid', pg_temp.paid('live', 'n1v', array['n1'])::text);
select pg_temp.check((pg_temp.tx('n_paid')::jsonb)->>'status' = 'invoiced' and (select count(*) from pg_temp.vinvoices('n1v')) = 1
    and (select array_agg(distinct public.event_web_person_vip_state(p.id)) <@ array['none', 'pending', 'paid', 'refunded']
           from event_registration_people p where p.event_id = pg_temp.fx('ev')),
  'N1 an open checkout that is paid is invoiced as before; the website''s VIP states are still the contract''s four');

-- ═════ M 444 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m444 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m444),
  'M1 running 444 a second time changed no function');
select pg_temp.check((select before = after1 from r444),
  'M2 444''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 444 checks passed.';
end $$;
rollback;
