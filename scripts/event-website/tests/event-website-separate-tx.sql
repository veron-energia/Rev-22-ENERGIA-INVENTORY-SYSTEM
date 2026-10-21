-- The event website (436): the later-use rule and its override, one action per transaction.
--
-- event-website.sql runs in ONE transaction, so now() is one moment there: an
-- approval, a cancellation, a reopening and the invoices made around them all
-- carry the same time, and invoice.therapy_reviewed (which the approval of a
-- guided Refund or Cancel sets for its own refund) stays set until the end.
-- What depends on one action coming after another is run here as it happens:
-- each statement below is its own transaction (psql's autocommit), the
-- signed-in user is a session setting, and nothing is rolled back.
--
--   SX1 SAVE72 given on a later invoice: Refund in full carries the override;
--       the Finance panel's refund in full is refused; a part refund goes.
--   SX2 the Owner asks and allows Refund in full with a reason (refused
--       without one): refunded, both vouchers taken back, the VIP invoice's
--       audit log names the request and, once the approval is stored, the
--       reason (the owner, 21 Oct 2026, answer 3; the review of 21 Oct 2026).
--   SX3 staff ask; staff can neither approve it nor record the refund; a
--       Manager allows it with a reason.
--   SX4 the request raised before the later invoice: its approval first shows
--       the revised plan with the override, then goes with a reason.
--   SX5 a Cancel allowed with a reason, its money not recorded then: paid back
--       later in two parts, both go; the row written then quotes the reason.
--   SX6 a Cancel approved while nothing was given later; SAVE72 given after
--       the cancellation (which took the VIP vouchers back) is not counted:
--       its refund due is recorded in full (the review of 21 Oct 2026).
--   SX7 SAVE72 given before a direct cancellation: all its money back is
--       refused, saying what to do; S$50 goes, the last S$22 does not.
--   SX8 a pending request's id does not let the Finance panel refund the VIP
--       ticket in full, in the next transaction either; staff cannot approve.
--   SX9 a part refund of the whole ticket needs the override like Refund in
--       full.
--   SX10 a VIP refunded, SAVE72 given while refunded, reopened and paid again:
--       that SAVE72 is not counted; one given after the reopening is.
--   SX11 (the owner, 21 Oct 2026, R6-7) SAVE72 given while the VIP stood paid,
--       before a cancellation: once the invoice is reopened (paid again) it
--       still counts (Refund in full and Cancel carry the override, the
--       Finance panel refuses); one given while it stood cancelled does not.
--
-- It COMMITS what it makes (made-up names, @example.com, ACMA's fictional
-- +61 2 5550 phones): run it only on a throwaway copy of the stack, with
--   psql -v throwaway=1 -f scripts/event-website/tests/event-website-separate-tx.sql
-- It installs supabase/436 first when it is not there. Every check runs, then
-- the file fails if any did.
\set ON_ERROR_STOP on
\if :{?throwaway}
\else
\echo 'This file commits what it makes: run it only on a throwaway copy of the database, with -v throwaway=1.'
do $$ begin raise exception 'not run: -v throwaway=1 was not given'; end $$;
\endif
select current_database() = 'postgres' as on_hosted \gset
\if :on_hosted
do $$ begin raise exception 'not run: a database named postgres may be a hosted project''s; use a throwaway copy'; end $$;
\endif
select to_regprocedure('public.event_web_call(text,uuid,text,jsonb)') is null as need_436 \gset
\if :need_436
\ir ../../../supabase/436_event_website_registrations_and_vip.sql
\endif
set lock_timeout = '10s';
set statement_timeout = '300s';

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
-- The signed-in user, for the session (each statement is its own transaction).
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), false),
          set_config('request.jwt.claim.role', 'authenticated', false) $$;
create function pg_temp.as_service() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claim.role', 'service_role', false) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad(((pg_temp.tx('phbase')::int + n) % 10000)::text, 4, '0') $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 'ht436sx-' || lower(tag) || '-' || lower(pg_temp.tx('sfx')) || '@example.com' $$;
create function pg_temp.bid(prefix text, tag text) returns text language sql as
$$ select prefix || '-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || prefix || tag), 1, 8)) $$;
create function pg_temp.person(pos int, first text, last text, phone text, email text, days date[], vip boolean default false)
returns jsonb language sql as
$$ select jsonb_build_object('position', pos, 'first_name', first, 'last_name', last, 'phone', phone, 'email', email,
            'days', to_jsonb(days), 'vip', vip) $$;
create function pg_temp.call(kind text, typ text, body jsonb, req uuid default gen_random_uuid()) returns jsonb
language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_service();
  v := public.event_web_call(pg_temp.tx('hash:' || kind), case when typ in ('event_info','referral_info','person','sync') then null else req end,
                             typ, jsonb_build_object('type', typ, 'event', coalesce(body->>'event', pg_temp.tx('code'))) || (body - 'event'));
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), false);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), false);
  return v;
end $$;
create function pg_temp.register(kind text, tag text, people jsonb) returns jsonb language sql as
$$ select pg_temp.call(kind, 'register', jsonb_build_object('registration', jsonb_build_object(
     'registration_id', pg_temp.bid('REG', tag), 'submitted_at', now(), 'referral_code', null, 'people', people))) $$;
create function pg_temp.pid(answer jsonb, pos int) returns uuid language sql as
$$ select (x->>'person_id')::uuid from jsonb_array_elements(answer->'people') x where (x->>'position')::int = pos $$;
create function pg_temp.tok(answer jsonb, pos int) returns text language sql as
$$ select x->>'upgrade_token' from jsonb_array_elements(answer->'people') x where (x->>'position')::int = pos $$;
create function pg_temp.checkout(kind text, tag text, tokens text[]) returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_checkout', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', to_jsonb(tokens),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null),
     'livemode', true, 'checkout_opened_at', now() - interval '3 minutes'))) $$;
create function pg_temp.paid(kind text, tag text, tokens text[], cents int) returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_paid', jsonb_build_object('payment', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'provider', 'hitpay',
     'payment_request_id', gen_random_uuid(), 'payment_id', gen_random_uuid(),
     'amount_cents', cents, 'currency', 'SGD', 'livemode', true, 'paid_at', now() - interval '1 minute',
     'upgrade_tokens', to_jsonb(tokens),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null)))) $$;
create function pg_temp.ino(inv uuid) returns text language sql as $$ select invoice_no from invoices where id = inv $$;
create function pg_temp.st(inv uuid) returns text language sql as $$ select status::text || ' ' || paid_amount from invoices where id = inv $$;
create function pg_temp.ticket(inv uuid) returns uuid language sql as
$$ select id from invoice_items where invoice_id = inv and line_kind = 'event_ticket' $$;
create function pg_temp.payment(inv uuid) returns uuid language sql as
$$ select id from invoice_payments where invoice_id = inv order by created_at desc limit 1 $$;
-- The VIP vouchers of an invoice (its free voucher lines' benefits, replacements included), by status.
create function pg_temp.vcount(inv uuid, st text) returns bigint language sql as
$$ select count(*) from customer_reward_vouchers v
    where v.status = st and v.id in (select b.reward_voucher_id from invoice_benefit_values b join invoice_items it on it.id = b.invoice_item_id
                                      where b.invoice_id = inv and it.line_kind = 'voucher' and coalesce(it.is_foc, false)) $$;
-- The Finance panel: money back on the VIP ticket; "Record refund paid" on a cancelled invoice (no line).
create function pg_temp.panel_refund(inv uuid, amount numeric, req uuid default gen_random_uuid()) returns text language sql as
$$ select pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', inv,
     jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(inv), 'amount', amount)),
     jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(inv), 'amount', amount)), '[]', 'Refund', req)) $$;
create function pg_temp.refund_due_paid(inv uuid, amount numeric) returns text language sql as
$$ select pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', inv,
     jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', amount)),
     jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(inv), 'amount', amount)), '[]', 'Refund paid', gen_random_uuid())) $$;
-- A later invoice of that customer with SAVE72 as its discount voucher.
create function pg_temp.save72_invoice(cust uuid) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx('van'), cust,
     jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('mat'), 'quantity', 1)),
     jsonb_build_object('business_date', public.sg_today(), 'manual_discount', 0, 'discount_voucher_id', pg_temp.fx('save72'))) $$;
create function pg_temp.later_ov(plan jsonb) returns jsonb language sql as
$$ select o from jsonb_array_elements(coalesce(plan->'overrides_required', '[]'::jsonb)) o where o->>'code' = 'vip_voucher_used_later' $$;
create function pg_temp.allowed_rows(inv uuid) returns bigint language sql as
$$ select count(*) from audit_logs a where a.record_id = inv and a.action = 'vip_refund_used_later_allowed' $$;
create function pg_temp.reason_rows(inv uuid) returns bigint language sql as
$$ select count(*) from audit_logs a where a.record_id = inv and a.action = 'vip_refund_used_later_reason' $$;
create function pg_temp.req(key text) returns uuid language sql as $$ select (pg_temp.tx(key)::jsonb->>'request_id')::uuid $$;
create function pg_temp.hash(key text) returns text language sql as $$ select pg_temp.tx(key)::jsonb->'plan'->>'plan_hash' $$;
create function pg_temp.resolve(key text, overrides jsonb, record_refund boolean default false, hash text default null) returns text language sql as
$$ select pg_temp.err(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, %L)', pg_temp.req(key), 'Approved',
     coalesce(hash, pg_temp.hash(key)), overrides, record_refund)) $$;
create function pg_temp.reason(why text) returns jsonb language sql as
$$ select jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', why)) $$;
create function pg_temp.later_cancelled_msg(holder text, later uuid, vip uuid) returns text language sql as
$$ select 'A discount with the HT436SX $72 discount Voucher was given to ' || holder || ' on ' || pg_temp.ino(later) || ', an invoice made '
          || 'after the VIP invoice ' || pg_temp.ino(vip) || ' and before it was cancelled, so the money it holds is not all paid back here: '
          || 'it was cancelled without an Owner''s or Manager''s override for that. Record a part refund, less than it holds; or an Owner '
          || 'or Manager reopens the invoice and cancels it again with the guided Cancel. Nothing was recorded.' $$;

-- ═════ Fixtures (committed) ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; ev uuid; src uuid; pm uuid; v1 uuid; v2 uuid; p uuid;
begin
  insert into tx values ('sfx', sfx), ('phbase', (floor(random() * 9000))::int::text);
  foreach k in array array['owner', 'acting', 'manager', 'staff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'ht436sx-' || k || '-' || lower(sfx) || '@example.com');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'HT436SX ' || initcap(k) || ' ' || sfx, 'ht436sx-' || k || '-' || lower(sfx) || '@example.com',
            case k when 'owner' then 'owner' when 'acting' then 'owner' when 'manager' then 'manager' else 'staff' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('HT436SX Van ' || sfx, 'HTSXV' || sfx, 'SG') returning id into st;
  insert into fx values ('van', st);
  insert into user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st);
  ev := public.event_save(jsonb_build_object('name', 'HT436SX Health Seminar ' || sfx, 'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st), 'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev', ev), ('vip', (select id from public.event_ticket_options where event_id = ev));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('HT436SX Event ' || sfx, true, true, 9999) returning id into src;
  insert into fx values ('src', src);
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('HT436SX $72 discount Voucher', 'HTSX72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('HT436SX 3-in-1 Vouchers', 'HTSX31' || sfx, 'normal', 'unlimited', 216, true) returning id into v2;
  insert into fx values ('save72', v1), ('three', v2);
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v1, st, 72, true), (v2, st, 216, true);
  insert into products(name, sku, product_type) values ('HT436SX Massage Mat', 'HTSX-MM-' || sfx, 'own') returning id into p;
  insert into store_product_prices(store_id, product_id, selling_price) values (st, p, 100);
  insert into store_inventory(store_id, product_id, current_qty) values (st, p, 50);
  insert into fx values ('mat', p);
end $$;
select pg_temp.as_user('owner');
insert into tx values ('code', 'HTSX-' || pg_temp.tx('sfx'));
select public.event_web_settings_save(pg_temp.fx('ev'), jsonb_build_object('code', pg_temp.tx('code'), 'mode', 'live', 'venue', null,
  'store_id', pg_temp.fx('van'), 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
  'vip_voucher_ids', jsonb_build_array(pg_temp.fx('save72'), pg_temp.fx('three')), 'gift_product_ids', '[]'::jsonb,
  'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
  'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', pg_temp.fx('src'),
  'source_details', 'Health Seminar (website)', 'sync_url', null));
do $$ declare r jsonb; begin
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'separate-tx check');
  insert into tx values ('hash:live', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
end $$;

-- Ten website VIPs, paid together through HitPay: each has their own invoice, with both VIP vouchers held.
select pg_temp.put('reg', pg_temp.register('live', 'sx', jsonb_build_array(
  pg_temp.person(1, 'Sara', 'Panelrefused', pg_temp.ph(1), pg_temp.mail('sara'), array[pg_temp.d(7)], true),
  pg_temp.person(2, 'Opal', 'Ownerallows', pg_temp.ph(2), pg_temp.mail('opal'), array[pg_temp.d(7)], true),
  pg_temp.person(3, 'Milo', 'Managerallows', pg_temp.ph(3), pg_temp.mail('milo'), array[pg_temp.d(7)], true),
  pg_temp.person(4, 'Otto', 'Askedbefore', pg_temp.ph(4), pg_temp.mail('otto'), array[pg_temp.d(7)], true),
  pg_temp.person(5, 'Stan', 'Cancellater', pg_temp.ph(5), pg_temp.mail('stan'), array[pg_temp.d(8)], true),
  pg_temp.person(6, 'Vera', 'Cancelfirst', pg_temp.ph(6), pg_temp.mail('vera'), array[pg_temp.d(8)], true),
  pg_temp.person(7, 'Cat', 'Directcancel', pg_temp.ph(7), pg_temp.mail('cat'), array[pg_temp.d(8)], true),
  pg_temp.person(8, 'Pat', 'Pendingpanel', pg_temp.ph(8), pg_temp.mail('pat'), array[pg_temp.d(8)], true),
  pg_temp.person(9, 'Oona', 'Partwhole', pg_temp.ph(9), pg_temp.mail('oona'), array[pg_temp.d(7)], true),
  pg_temp.person(10, 'Oda', 'Between', pg_temp.ph(10), pg_temp.mail('oda'), array[pg_temp.d(7)], true)))::text);
select pg_temp.checkout('live', 'sx', array(select pg_temp.tok(pg_temp.tx('reg')::jsonb, n) from generate_series(1, 10) n));
select pg_temp.put('paid', (pg_temp.paid('live', 'sx', array(select pg_temp.tok(pg_temp.tx('reg')::jsonb, n) from generate_series(1, 10) n), 72000))->>'status');
select pg_temp.putx('inv_' || k, (select op.invoice_id from event_vip_order_people op where op.person_id = pg_temp.pid(pg_temp.tx('reg')::jsonb, n::int)))
  from unnest(array['sara', 'opal', 'milo', 'otto', 'stan', 'vera', 'cat', 'pat', 'oona', 'oda']) with ordinality x(k, n);
select pg_temp.putx('c_' || k, (select customer_id from invoices where id = pg_temp.fx('inv_' || k)))
  from unnest(array['sara', 'opal', 'milo', 'otto', 'stan', 'vera', 'cat', 'pat', 'oona', 'oda']) k;
select pg_temp.check(pg_temp.tx('paid') = 'invoiced'
    and (select count(*) from unnest(array['sara', 'opal', 'milo', 'otto', 'stan', 'vera', 'cat', 'pat', 'oona', 'oda']) k
          where pg_temp.st(pg_temp.fx('inv_' || k)) = 'paid 72.00' and pg_temp.vcount(pg_temp.fx('inv_' || k), 'held') = 2) = 10,
  'SX0 ten website VIPs paid together: ten invoices, each holding both VIP vouchers');

-- Otto's request is raised now, before his later invoice (SX4); Vera's Cancel is approved now, before hers (SX6).
select pg_temp.as_user('staff');
select pg_temp.put('otto_req', public.request_invoice_action_v2(pg_temp.fx('inv_otto'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.put('vera_req', public.request_invoice_action_v2(pg_temp.fx('inv_vera'), 'cancel', '[]', 'Wrong day', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('vera_res', pg_temp.resolve('vera_req', '[]'));
select pg_temp.put('vera_mid', pg_temp.st(pg_temp.fx('inv_vera')) || ' held=' || pg_temp.vcount(pg_temp.fx('inv_vera'), 'held'));
-- Then each of the others (and Otto and Vera) is given SAVE72 on a later invoice, Cat's before her cancellation.
select pg_temp.as_user('owner');
select pg_temp.putx('later_' || k, pg_temp.save72_invoice(pg_temp.fx('c_' || k)))
  from unnest(array['sara', 'opal', 'milo', 'otto', 'stan', 'cat', 'pat', 'oona']) k;
select pg_temp.putx('later_vera', pg_temp.save72_invoice(pg_temp.fx('c_vera')));

-- SX1
select pg_temp.as_user('staff');
select pg_temp.put('sara_plan', public.invoice_action_plan(pg_temp.fx('inv_sara'), 'refund_full', '[]')::text);
select pg_temp.as_user('owner');
select pg_temp.put('sara_full', pg_temp.panel_refund(pg_temp.fx('inv_sara'), 72));
select pg_temp.put('sara_part', pg_temp.panel_refund(pg_temp.fx('inv_sara'), 30));
select pg_temp.check(pg_temp.later_ov(pg_temp.tx('sara_plan')::jsonb)->>'invoice_no' = pg_temp.ino(pg_temp.fx('later_sara'))
    and pg_temp.tx('sara_full') like 'A discount with the HT436SX $72 discount Voucher was given to Sara Panelrefused on '
                                     || pg_temp.ino(pg_temp.fx('later_sara')) || '%Use Refund in full on the invoice%'
    and pg_temp.tx('sara_part') = 'ok' and (select paid_amount from invoices where id = pg_temp.fx('inv_sara')) = 42
    and pg_temp.vcount(pg_temp.fx('inv_sara'), 'held') = 2,
  'SX1 SAVE72 on a later invoice: Refund in full carries the override naming it; the Finance panel''s refund in full is refused; S$30 back goes (still VIP, both vouchers held): '
  || pg_temp.tx('sara_full'));

-- SX2
select pg_temp.put('opal_req', public.request_invoice_action_v2(pg_temp.fx('inv_opal'), 'refund_full', '[]', 'Cannot come after all', null, gen_random_uuid())::text);
select pg_temp.put('opal_none', pg_temp.resolve('opal_req', '[]'));
select pg_temp.put('opal_res', pg_temp.resolve('opal_req', pg_temp.reason('Her SAVE72 on the mat was the shop''s own offer')));
-- The approval's own setting (invoice.therapy_reviewed, for its refund) is gone in the next transaction.
select pg_temp.put('opal_guc', coalesce(current_setting('invoice.therapy_reviewed', true), ''));
select pg_temp.check(pg_temp.later_ov(pg_temp.tx('opal_req')::jsonb->'plan') is not null
    and pg_temp.tx('opal_none') = 'An Owner/Manager override reason is required for: vip_voucher_used_later'
    and pg_temp.tx('opal_res') = 'ok' and pg_temp.tx('opal_guc') = '' and pg_temp.st(pg_temp.fx('inv_opal')) = 'refunded 0.00'
    and pg_temp.vcount(pg_temp.fx('inv_opal'), 'revoked') = 2 and pg_temp.vcount(pg_temp.fx('inv_opal'), 'held') = 0
    and pg_temp.allowed_rows(pg_temp.fx('inv_opal')) = 1 and pg_temp.reason_rows(pg_temp.fx('inv_opal')) = 1
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_opal') and a.action = 'vip_refund_used_later_allowed'
                  and a.new_data @> jsonb_build_object('request_id', pg_temp.req('opal_req'), 'allowed_by', pg_temp.fx('owner')))
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_opal') and a.action = 'vip_refund_used_later_reason'
                  and a.new_data @> jsonb_build_object('request_id', pg_temp.req('opal_req'), 'allowed_by', pg_temp.fx('owner'),
                                                       'reason', 'Her SAVE72 on the mat was the shop''s own offer')),
  'SX2 the Owner allows Refund in full with a reason (refused without one): refunded, both vouchers taken back; the VIP invoice''s audit log names the request and gives the reason: '
  || pg_temp.tx('opal_none'));

-- SX3
select pg_temp.as_user('staff');
select pg_temp.put('milo_req', public.request_invoice_action_v2(pg_temp.fx('inv_milo'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.put('milo_staff', pg_temp.resolve('milo_req', pg_temp.reason('Staff allow it')));
select pg_temp.put('milo_staff_panel', pg_temp.panel_refund(pg_temp.fx('inv_milo'), 72));
select pg_temp.as_user('manager');
select pg_temp.put('milo_res', pg_temp.resolve('milo_req', pg_temp.reason('Agreed with the Owner by phone')));
select pg_temp.check(pg_temp.tx('milo_staff') = 'Only an Owner or Manager can approve or reject an invoice request'
    and pg_temp.tx('milo_staff_panel') = 'Only an Owner or Manager can record a refund'
    and pg_temp.tx('milo_res') = 'ok' and pg_temp.st(pg_temp.fx('inv_milo')) = 'refunded 0.00'
    and pg_temp.vcount(pg_temp.fx('inv_milo'), 'revoked') = 2
    and pg_temp.reason_rows(pg_temp.fx('inv_milo')) = 1
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_milo') and a.action = 'vip_refund_used_later_reason'
                  and a.new_data @> jsonb_build_object('allowed_by', pg_temp.fx('manager'), 'reason', 'Agreed with the Owner by phone')),
  'SX3 staff ask, but cannot approve it or record the refund; a Manager allows it with a reason: refunded, the reason in the VIP invoice''s audit log: '
  || pg_temp.tx('milo_staff'));

-- SX4
select pg_temp.as_user('manager');
select pg_temp.put('otto_old', public.resolve_invoice_action_v2(pg_temp.req('otto_req'), true, 'Approved', pg_temp.hash('otto_req'),
  pg_temp.reason('Separate offer'), null, false)::text);
select pg_temp.put('otto_mid', pg_temp.st(pg_temp.fx('inv_otto')));
select pg_temp.put('otto_res', pg_temp.resolve('otto_req', pg_temp.reason('Separate offer'), false,
  pg_temp.tx('otto_old')::jsonb->'revised_plan'->>'plan_hash'));
select pg_temp.check(pg_temp.later_ov(pg_temp.tx('otto_req')::jsonb->'plan') is null
    and (pg_temp.tx('otto_old')::jsonb)->>'confirmation_required' = 'true' and pg_temp.tx('otto_mid') = 'paid 72.00'
    and pg_temp.later_ov(pg_temp.tx('otto_old')::jsonb->'revised_plan') is not null
    and pg_temp.tx('otto_res') = 'ok' and pg_temp.st(pg_temp.fx('inv_otto')) = 'refunded 0.00'
    and pg_temp.allowed_rows(pg_temp.fx('inv_otto')) = 1 and pg_temp.reason_rows(pg_temp.fx('inv_otto')) = 1,
  'SX4 asked for before the later invoice: its approval first shows the revised plan with the override (nothing done), then goes with a reason: '
  || left(pg_temp.tx('otto_old'), 120));

-- SX5
select pg_temp.as_user('staff');
select pg_temp.put('stan_req', public.request_invoice_action_v2(pg_temp.fx('inv_stan'), 'cancel', '[]', 'Wrong day', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('stan_res', pg_temp.resolve('stan_req', pg_temp.reason('The later SAVE72 was a separate offer')));
select pg_temp.put('stan_mid', pg_temp.st(pg_temp.fx('inv_stan')));
select pg_temp.as_user('owner');
select pg_temp.put('stan_part', pg_temp.refund_due_paid(pg_temp.fx('inv_stan'), 30));
select pg_temp.put('stan_rest', pg_temp.refund_due_paid(pg_temp.fx('inv_stan'), 42));
select pg_temp.check(pg_temp.later_ov(pg_temp.tx('stan_req')::jsonb->'plan') is not null
    and pg_temp.tx('stan_res') = 'ok' and pg_temp.tx('stan_mid') = 'cancelled 72.00'
    and pg_temp.tx('stan_part') = 'ok' and pg_temp.tx('stan_rest') = 'ok' and pg_temp.st(pg_temp.fx('inv_stan')) = 'cancelled 0.00'
    and pg_temp.vcount(pg_temp.fx('inv_stan'), 'held') = 0
    and pg_temp.allowed_rows(pg_temp.fx('inv_stan')) = 1 and pg_temp.reason_rows(pg_temp.fx('inv_stan')) = 0
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_stan') and a.action = 'vip_refund_used_later_allowed'
                  and a.new_data @> jsonb_build_object('allowed_by', pg_temp.fx('manager'), 'reason', 'The later SAVE72 was a separate offer')),
  'SX5 a Cancel allowed with a reason, its money not recorded then: paid back later in two parts, both go; the row written then quotes the reason: '
  || pg_temp.tx('stan_part') || ' ' || pg_temp.tx('stan_rest'));

-- SX6 (the review of 21 Oct 2026)
select pg_temp.put('vera_seen', coalesce(public.event_vip_used_later(pg_temp.fx('inv_vera'))::text, 'none'));
select pg_temp.put('vera_paid', pg_temp.refund_due_paid(pg_temp.fx('inv_vera'), 72));
select pg_temp.check(pg_temp.later_ov(pg_temp.tx('vera_req')::jsonb->'plan') is null
    and pg_temp.tx('vera_res') = 'ok' and pg_temp.tx('vera_mid') = 'cancelled 72.00 held=0'
    and (select l.created_at > a.created_at from invoices l, audit_logs a
          where l.id = pg_temp.fx('later_vera') and a.record_id = pg_temp.fx('inv_vera') and a.action = 'invoice_cancelled')
    and pg_temp.tx('vera_seen') = 'none' and pg_temp.tx('vera_paid') = 'ok' and pg_temp.st(pg_temp.fx('inv_vera')) = 'cancelled 0.00'
    and pg_temp.allowed_rows(pg_temp.fx('inv_vera')) = 0,
  'SX6 a Cancel approved before any later discount; SAVE72 given after the cancellation (which took the VIP vouchers back) is not counted: its S$72 refund due is recorded in full: '
  || pg_temp.tx('vera_paid'));

-- SX7
select pg_temp.put('cat_cancel', pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, %L)', pg_temp.fx('inv_cat'), 'Wrong day', gen_random_uuid())));
select pg_temp.put('cat_all', pg_temp.refund_due_paid(pg_temp.fx('inv_cat'), 72));
select pg_temp.put('cat_part', pg_temp.refund_due_paid(pg_temp.fx('inv_cat'), 50));
select pg_temp.put('cat_rest', pg_temp.refund_due_paid(pg_temp.fx('inv_cat'), 22));
select pg_temp.check(pg_temp.tx('cat_cancel') = 'ok'
    and pg_temp.tx('cat_all') = pg_temp.later_cancelled_msg('Cat Directcancel', pg_temp.fx('later_cat'), pg_temp.fx('inv_cat'))
    and pg_temp.tx('cat_part') = 'ok' and pg_temp.tx('cat_rest') = pg_temp.tx('cat_all')
    and pg_temp.st(pg_temp.fx('inv_cat')) = 'cancelled 22.00',
  'SX7 SAVE72 given before a direct cancellation: all its money back is refused, saying what to do; S$50 goes, the last S$22 does not: '
  || pg_temp.tx('cat_all'));

-- SX8
select pg_temp.as_user('staff');
select pg_temp.put('pat_req', public.request_invoice_action_v2(pg_temp.fx('inv_pat'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.put('pat_staff', pg_temp.resolve('pat_req', pg_temp.reason('x')));
select pg_temp.as_user('owner');
select pg_temp.put('pat_panel', pg_temp.panel_refund(pg_temp.fx('inv_pat'), 72, pg_temp.req('pat_req')));
select pg_temp.put('pat_panel2', pg_temp.panel_refund(pg_temp.fx('inv_pat'), 72));
select pg_temp.check(pg_temp.tx('pat_staff') = 'Only an Owner or Manager can approve or reject an invoice request'
    and pg_temp.tx('pat_panel') like 'A discount with the %Use Refund in full on the invoice%'
    and pg_temp.tx('pat_panel2') = pg_temp.tx('pat_panel')
    and pg_temp.st(pg_temp.fx('inv_pat')) = 'paid 72.00'
    and (select status::text from approval_requests where id = pg_temp.req('pat_req')) = 'pending',
  'SX8 the Finance panel cannot refund the VIP ticket in full, also when it names a pending request; staff cannot approve: '
  || pg_temp.tx('pat_panel'));

-- SX9
select pg_temp.put('oona_req', public.request_invoice_action_v2(pg_temp.fx('inv_oona'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_oona')), 'quantity', 1)), 'Part', null, gen_random_uuid())::text);
select pg_temp.put('oona_none', pg_temp.resolve('oona_req', '[]'));
select pg_temp.put('oona_res', pg_temp.resolve('oona_req', pg_temp.reason('Owner allows')));
select pg_temp.check(pg_temp.later_ov(pg_temp.tx('oona_req')::jsonb->'plan') is not null
    and pg_temp.tx('oona_none') = 'An Owner/Manager override reason is required for: vip_voucher_used_later'
    and pg_temp.tx('oona_res') = 'ok' and pg_temp.st(pg_temp.fx('inv_oona')) = 'refunded 0.00'
    and pg_temp.reason_rows(pg_temp.fx('inv_oona')) = 1,
  'SX9 a part refund of the whole ticket needs the override as Refund in full: refused without a reason, done with one: ' || pg_temp.tx('oona_none'));

-- SX10
select pg_temp.put('oda_r1', pg_temp.panel_refund(pg_temp.fx('inv_oda'), 72));
select pg_temp.putx('oda_between', pg_temp.save72_invoice(pg_temp.fx('c_oda')));
select pg_temp.put('oda_reopen', pg_temp.err(format('select public.reopen_invoice(%L, %L, %L)', pg_temp.fx('inv_oda'), 'Refunded by mistake', gen_random_uuid())));
select pg_temp.put('oda_pay', pg_temp.err(format('select public.record_invoice_payment(%L, %L, %L)', pg_temp.fx('inv_oda'),
  jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('bank'), 'amount', 72, 'reference', 'Paid again',
                                       'payment_date', public.sg_today())), gen_random_uuid())));
select pg_temp.as_user('staff');
select pg_temp.put('oda_plan', public.invoice_action_plan(pg_temp.fx('inv_oda'), 'refund_full', '[]')::text);
select pg_temp.as_user('owner');
select pg_temp.putx('oda_after', pg_temp.save72_invoice(pg_temp.fx('c_oda')));
select pg_temp.as_user('staff');
select pg_temp.put('oda_plan2', public.invoice_action_plan(pg_temp.fx('inv_oda'), 'refund_full', '[]')::text);
select pg_temp.check(pg_temp.tx('oda_r1') = 'ok' and pg_temp.tx('oda_reopen') = 'ok' and pg_temp.tx('oda_pay') = 'ok'
    and pg_temp.st(pg_temp.fx('inv_oda')) = 'paid 72.00'
    and pg_temp.later_ov(pg_temp.tx('oda_plan')::jsonb) is null
    and pg_temp.later_ov(pg_temp.tx('oda_plan2')::jsonb)->>'invoice_no' = pg_temp.ino(pg_temp.fx('oda_after')),
  'SX10 SAVE72 given while the VIP stood refunded is not counted once it is reopened and paid again; one given after the reopening is: '
  || coalesce(pg_temp.later_ov(pg_temp.tx('oda_plan2')::jsonb)->>'invoice_no', '(none)'));

-- SX11 (the owner, 21 Oct 2026, R6-7)
select pg_temp.as_user('owner');
select pg_temp.put('reg11', pg_temp.register('live', 'sx11', jsonb_build_array(
  pg_temp.person(1, 'Rhea', 'Reopened', pg_temp.ph(11), pg_temp.mail('rhea'), array[pg_temp.d(7)], true),
  pg_temp.person(2, 'Remy', 'Gapcancel', pg_temp.ph(12), pg_temp.mail('remy'), array[pg_temp.d(7)], true)))::text);
select pg_temp.checkout('live', 'sx11', array[pg_temp.tok(pg_temp.tx('reg11')::jsonb, 1), pg_temp.tok(pg_temp.tx('reg11')::jsonb, 2)]);
select pg_temp.put('paid11', (pg_temp.paid('live', 'sx11', array[pg_temp.tok(pg_temp.tx('reg11')::jsonb, 1),
  pg_temp.tok(pg_temp.tx('reg11')::jsonb, 2)], 14400))->>'status');
select pg_temp.putx('inv_' || k, (select op.invoice_id from event_vip_order_people op where op.person_id = pg_temp.pid(pg_temp.tx('reg11')::jsonb, n::int)))
  from unnest(array['rhea', 'remy']) with ordinality x(k, n);
select pg_temp.putx('c_' || k, (select customer_id from invoices where id = pg_temp.fx('inv_' || k))) from unnest(array['rhea', 'remy']) k;
-- Rhea: SAVE72 given while her VIP stood paid; then her VIP invoice is cancelled and reopened (its money still held: paid again).
select pg_temp.putx('later_rhea', pg_temp.save72_invoice(pg_temp.fx('c_rhea')));
select pg_temp.put('rhea_cancel', pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, %L)', pg_temp.fx('inv_rhea'), 'Wrong day', gen_random_uuid())));
select pg_temp.put('rhea_reopen', pg_temp.err(format('select public.reopen_invoice(%L, %L, %L)', pg_temp.fx('inv_rhea'), 'Cancelled by mistake', gen_random_uuid())));
-- Remy: cancelled first; SAVE72 given while it stood cancelled; then reopened.
select pg_temp.put('remy_cancel', pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, %L)', pg_temp.fx('inv_remy'), 'Wrong day', gen_random_uuid())));
select pg_temp.putx('later_remy', pg_temp.save72_invoice(pg_temp.fx('c_remy')));
select pg_temp.put('remy_reopen', pg_temp.err(format('select public.reopen_invoice(%L, %L, %L)', pg_temp.fx('inv_remy'), 'Cancelled by mistake', gen_random_uuid())));
select pg_temp.as_user('staff');
select pg_temp.put('rhea_plan', public.invoice_action_plan(pg_temp.fx('inv_rhea'), 'refund_full', '[]')::text);
select pg_temp.put('rhea_cplan', public.invoice_action_plan(pg_temp.fx('inv_rhea'), 'cancel', '[]')::text);
select pg_temp.put('remy_plan', public.invoice_action_plan(pg_temp.fx('inv_remy'), 'refund_full', '[]')::text);
select pg_temp.as_user('owner');
select pg_temp.put('rhea_panel', pg_temp.panel_refund(pg_temp.fx('inv_rhea'), 72));
select pg_temp.check(pg_temp.tx('paid11') = 'invoiced' and pg_temp.tx('rhea_cancel') = 'ok' and pg_temp.tx('rhea_reopen') = 'ok'
    and pg_temp.tx('remy_cancel') = 'ok' and pg_temp.tx('remy_reopen') = 'ok'
    and pg_temp.st(pg_temp.fx('inv_rhea')) = 'paid 72.00' and pg_temp.st(pg_temp.fx('inv_remy')) = 'paid 72.00'
    and pg_temp.later_ov(pg_temp.tx('rhea_plan')::jsonb)->>'invoice_no' = pg_temp.ino(pg_temp.fx('later_rhea'))
    and pg_temp.later_ov(pg_temp.tx('rhea_cplan')::jsonb)->>'invoice_no' = pg_temp.ino(pg_temp.fx('later_rhea'))
    and pg_temp.tx('rhea_panel') like 'A discount with the HT436SX $72 discount Voucher was given to Rhea Reopened on '
                                      || pg_temp.ino(pg_temp.fx('later_rhea')) || '%Use Refund in full on the invoice%'
    and pg_temp.later_ov(pg_temp.tx('remy_plan')::jsonb) is null,
  'SX11 SAVE72 given before the VIP invoice was cancelled still counts once it is reopened and paid again (Refund in full and Cancel carry the override, the Finance panel refuses); one given while it stood cancelled does not: '
  || coalesce(pg_temp.later_ov(pg_temp.tx('rhea_plan')::jsonb)->>'invoice_no', '(none)') || ' / ' || pg_temp.tx('rhea_panel'));

select pg_temp.as_user('owner');
do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All event-website separate-transaction checks passed.';
end $$;
