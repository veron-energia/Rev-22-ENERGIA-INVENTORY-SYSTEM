-- Payment methods: system wallet names, names unique among live methods, and
-- what the website order channels use (429).
--
-- ADMIN-AUTH-10: a system wallet method (one of the five Wallet credit types)
-- could be renamed or switched off; the page could not tell which methods the
-- website order channels use, so it could not warn before one was switched
-- off.
-- ADMIN-AUTH-11: a deleted method's name could never be used again.
--
--   1. A system wallet method cannot be renamed, switched off or deleted, by
--      a page or by the server (the Owner, 10 Oct 2026: the five Wallet
--      credit types are never switched off). One found off can be switched
--      on, and then not off again.
--   2. Other methods are renamed and switched off as before.
--   3. Names are unique among live methods, ignoring case and outer spaces;
--      a deleted method's name is used again, and the old method can be
--      restored once no live method has its name.
--   4. Staff still cannot write payment methods.
--   5. payment_method_web_uses() answers Owners and Managers with each
--      channel's method, its HitPay method (or the active "HitPay (online)"
--      when it names none) and its door methods; it refuses everyone else.
--   6. Grants and the catalogue.
--
-- It needs a database with production's schema and 406 to 429 applied, or 429
-- given as the prelude:
--   psql -v prelude=supabase/429_users_invitations_and_payment_methods.sql -f this
-- Disposable database only; everything is rolled back. Fixture names start
-- "429P", logins are @sig.invalid; nothing real is read or printed.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif
do $$
begin
  -- 429's protection of the system wallet methods, or 443's (which also
  -- keeps a method's wallet_source).
  if to_regprocedure('public.payment_method_web_uses()') is null
     or md5(pg_get_functiondef('public.trg_protect_system_payment_methods()'::regprocedure))
        not in ('9c1af002437091b7ef61b04221b254eb', '74bca50e1b15f8b5b61a17ce6a350c5a') then
    raise exception '429 is not in this database: run with -v prelude=supabase/429_users_invitations_and_payment_methods.sql (see the header)'; end if;
end $$;

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;

create temp table fx(k text primary key, id uuid not null);
create function pg_temp.fx(p text) returns uuid language sql as $f$ select id from fx where k = p $f$;
create temp table out(k text primary key, v jsonb);
create function pg_temp.out(p text) returns jsonb language sql as $f$ select v from out where k = p $f$;

-- Run p_sql as a fixture login, 'anon' or 'server', require p_expect ('ok' or
-- a SQLSTATE), keep the jsonb it returns under p_keep, and the error message
-- under p_keep || '_msg'.
create function pg_temp.run(p_who text, p_sql text, p_expect text, p_label text, p_keep text default null)
returns void language plpgsql as $f$
declare v_state text := 'ok'; v_msg text; r record; v_ret jsonb;
begin
  for r in select k, id from fx loop
    p_sql := replace(p_sql, format('pg_temp.fx(%L)', r.k), format('%L::uuid', r.id));
  end loop;
  begin
    if p_who = 'server' then
      perform set_config('request.jwt.claims', '', true);
    elsif p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.fx(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v_ret;
    execute 'reset role';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    execute 'reset role';
  end;
  perform set_config('request.jwt.claims', '', true);
  if v_state is distinct from p_expect then
    raise exception 'FAIL: % (expected %, got % %)', p_label, p_expect, v_state, coalesce(v_msg, ''); end if;
  if p_keep is not null then
    insert into out values (p_keep, v_ret) on conflict (k) do update set v = excluded.v;
    insert into out values (p_keep || '_msg', to_jsonb(v_msg)) on conflict (k) do update set v = excluded.v;
  end if;
  raise notice 'PASS  %', p_label;
end $f$;

-- ── Fixture (written as the server would) ────────────────────────────────────
do $$
declare k text; v uuid; v_event uuid; v_store uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner','manager','staff','affiliate'] loop
    insert into auth.users (id, email) values (gen_random_uuid(), '429p-' || k || '@sig.invalid') returning id into v;
    insert into fx values (k, v);
  end loop;
  insert into public.profiles (id, full_name, email, role, is_active)
  select fx.id, '429P ' || fx.k, '429p-' || fx.k || '@sig.invalid', fx.k::public.user_role, true
    from fx where fx.k in ('owner', 'manager', 'staff');
  insert into public.payment_methods (name, is_wallet_credit, wallet_category, is_system)
  values ('429P Wallet Paid', true, 'paid', true) returning id into v;
  insert into fx values ('wallet', v);
  insert into public.payment_methods (name) values ('429P Card') returning id into v;      insert into fx values ('card', v);
  insert into public.payment_methods (name) values ('429P Stripe') returning id into v;    insert into fx values ('stripe', v);
  -- Production already has a live "HitPay (online)", and live names are
  -- unique: use it if there is one (switched on, as the channels need it;
  -- rolled back), else make one.
  v := null;
  select m.id into v from public.payment_methods m
   where lower(m.name) = lower('HitPay (online)') and m.deleted_at is null
   order by m.is_active desc, m.created_at limit 1;
  if v is null then
    insert into public.payment_methods (name) values ('HitPay (online)') returning id into v;
  else
    update public.payment_methods set is_active = true where id = v and not is_active;
  end if;
  insert into fx values ('hitpay', v);
  insert into public.payment_methods (name) values ('429P HitPay Two') returning id into v; insert into fx values ('hitpay2', v);
  insert into public.payment_methods (name) values ('429P Cash') returning id into v;      insert into fx values ('cash', v);
  insert into public.stores (name, code) values ('429P Store', '429P') returning id into v_store;
  insert into public.events (name) values ('429P Event') returning id into v_event;
  -- One channel naming no HitPay method (the active "HitPay (online)" stands
  -- in, as web_order_payment_method() reads it), with a door method and a
  -- door value that is not a method id; another naming its HitPay method.
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id,
                                         hitpay_payment_method_id, door_methods, mode)
  values ('429p-one', v_event, '{}', v_store, pg_temp.fx('owner'), pg_temp.fx('stripe'), null,
          jsonb_build_object('cash', pg_temp.fx('cash'), 'note', 'not a method', 'count', 3), 'live'),
         ('429p-two', v_event, '{}', v_store, pg_temp.fx('owner'), pg_temp.fx('stripe'), pg_temp.fx('hitpay2'), '{}', 'off');
end $$;

-- ── 1. A system wallet method keeps its name ─────────────────────────────────
select pg_temp.run('owner', $q$update public.payment_methods set name = '429P Wallet Renamed'
    where id = pg_temp.fx('wallet') returning to_jsonb(name)$q$, 'P0001',
  'wallet: an Owner renames a system wallet method on Payment Methods', 'rename');
select pg_temp.check(pg_temp.out('rename_msg') = to_jsonb('A system wallet payment method cannot be renamed'::text)
                     and (select name from public.payment_methods where id = pg_temp.fx('wallet')) = '429P Wallet Paid',
  'wallet: refused, and the name is unchanged (before 429 it was renamed)');
select pg_temp.run('server', $q$update public.payment_methods set name = name || ' x' where id = pg_temp.fx('wallet')
    returning to_jsonb(name)$q$, 'P0001', 'wallet: the server cannot rename it either');
select pg_temp.run('manager', $q$update public.payment_methods set deleted_at = now(), is_active = false
    where id = pg_temp.fx('wallet') returning to_jsonb(name)$q$, 'P0001', 'wallet: a Manager cannot delete it (as before)');
select pg_temp.run(w, $q$update public.payment_methods set is_active = false
    where id = pg_temp.fx('wallet') returning to_jsonb(is_active)$q$, 'P0001',
  'wallet: ' || w || ' cannot switch it off (before 429 it could)', 'off_' || w)
  from unnest(array['manager', 'owner', 'server']) w;
select pg_temp.check(pg_temp.out('off_manager_msg') = to_jsonb('A system wallet payment method cannot be switched off'::text)
                     and pg_temp.out('off_owner_msg') = pg_temp.out('off_manager_msg')
                     and (select is_active from public.payment_methods where id = pg_temp.fx('wallet')),
  'wallet: refused with a plain reason, and it stays on');
select pg_temp.run('manager', $q$update public.payment_methods set is_active = true
    where id = pg_temp.fx('wallet') returning to_jsonb(is_active)$q$, 'ok',
  'wallet: a save that leaves it on is accepted');
-- One found off (written as the server would; the rule is on switching off).
insert into public.payment_methods (name, is_wallet_credit, wallet_category, is_system, is_active)
values ('429P Wallet Bonus', true, 'bonus', true, false);
select pg_temp.run('manager', $q$update public.payment_methods set is_active = true
    where name = '429P Wallet Bonus' returning to_jsonb(is_active)$q$, 'ok',
  'wallet: a Manager switches on one found off', 'on');
select pg_temp.run('manager', $q$update public.payment_methods set is_active = false
    where name = '429P Wallet Bonus' returning to_jsonb(is_active)$q$, 'P0001',
  'wallet: and cannot switch it off again');
select pg_temp.check(pg_temp.out('on') = 'true'::jsonb
                     and (select is_active from public.payment_methods where name = '429P Wallet Bonus'),
  'wallet: it is on');

-- ── 2. Other methods are renamed as before ───────────────────────────────────
select pg_temp.run('manager', $q$update public.payment_methods set name = '429P Card Renamed'
    where id = pg_temp.fx('card') returning to_jsonb(name)$q$, 'ok', 'rename: a Manager renames an ordinary method', 'card');
select pg_temp.check(pg_temp.out('card') = '"429P Card Renamed"'::jsonb, 'rename: it is renamed');
select pg_temp.run('manager', $q$update public.payment_methods set is_active = false
    where id = pg_temp.fx('card') returning to_jsonb(is_active)$q$, 'ok', 'off: a Manager switches an ordinary method off', 'card_off');
select pg_temp.run('manager', $q$update public.payment_methods set is_active = true
    where id = pg_temp.fx('card') returning to_jsonb(is_active)$q$, 'ok', 'off: and on again');
select pg_temp.check(pg_temp.out('card_off') = 'false'::jsonb
                     and (select is_active from public.payment_methods where id = pg_temp.fx('card')),
  'off: ordinary methods are switched off and on as before');

-- ── 3. Names are unique among live methods ───────────────────────────────────
select pg_temp.run('owner', $q$insert into public.payment_methods (name) values ('429P Plan') returning to_jsonb(id)$q$, 'ok',
  'names: an Owner adds a method', 'plan_old');
select pg_temp.run('owner', $q$update public.payment_methods set deleted_at = now(), is_active = false
    where name = '429P Plan' returning to_jsonb(id)$q$, 'ok', 'names: and deletes it');
select pg_temp.run('owner', $q$insert into public.payment_methods (name) values (' 429p plan ') returning to_jsonb(id)$q$, 'ok',
  'names: the deleted method''s name is added again, in other letters and spaces (before 429: "already exists")', 'plan_new');
select pg_temp.run('owner', $q$insert into public.payment_methods (name) values ('429P PLAN') returning to_jsonb(id)$q$, '23505',
  'names: a second live method with that name is refused');
select pg_temp.run('owner', format($q$update public.payment_methods set deleted_at = null, is_active = true
    where id = %L returning to_jsonb(id)$q$, pg_temp.out('plan_old') #>> '{}'), '23505',
  'names: restoring the old one while a live method has its name is refused');
select pg_temp.run('owner', format($q$update public.payment_methods set deleted_at = now(), is_active = false
    where id = %L returning to_jsonb(id)$q$, pg_temp.out('plan_new') #>> '{}'), 'ok', 'names: the new one is deleted');
select pg_temp.run('owner', format($q$update public.payment_methods set deleted_at = null, is_active = true
    where id = %L returning to_jsonb(id)$q$, pg_temp.out('plan_old') #>> '{}'), 'ok',
  'names: then the old one is restored (the page offers Restore)');
select pg_temp.check((select count(*) from public.payment_methods where lower(btrim(name)) = '429p plan') = 2
                     and (select count(*) from public.payment_methods where lower(btrim(name)) = '429p plan' and deleted_at is null) = 1,
  'names: one live, one deleted, nothing lost');

-- ── 4. Staff still cannot write payment methods ──────────────────────────────
select pg_temp.run('staff', $q$insert into public.payment_methods (name) values ('429P Staff Method') returning to_jsonb(id)$q$, '42501',
  'staff: cannot add a method');
select pg_temp.run('staff', $q$with u as (update public.payment_methods set name = 'x' where id = pg_temp.fx('card') returning 1)
    select to_jsonb(count(*)) from u$q$, 'ok', 'staff: an update', 'staff_update');
select pg_temp.check(pg_temp.out('staff_update') = '0'::jsonb
                     and (select name from public.payment_methods where id = pg_temp.fx('card')) = '429P Card Renamed',
  'staff: changes nothing');

-- ── 5. What the website order channels use ───────────────────────────────────
select pg_temp.run(w, $q$select coalesce(jsonb_agg(jsonb_build_object('m', (select name from public.payment_methods m
      where m.id = x.payment_method_id), 'c', x.channel_key, 'mode', x.channel_mode, 'for', x.used_for)
      order by x.channel_key, x.used_for), '[]') from public.payment_method_web_uses() x where x.channel_key like '429p-%'$q$,
  'ok', 'web: ' || w || ' asks which methods the website channels use', 'web_' || w)
  from unnest(array['owner', 'manager']) w;
select pg_temp.check(pg_temp.out('web_owner') = jsonb_build_array(
      jsonb_build_object('m', '429P Cash', 'c', '429p-one', 'mode', 'live', 'for', 'payments at the door (cash)'),
      jsonb_build_object('m', '429P Stripe', 'c', '429p-one', 'mode', 'live', 'for', 'website orders'),
      jsonb_build_object('m', (select name from public.payment_methods where id = pg_temp.fx('hitpay')),
                         'c', '429p-one', 'mode', 'live', 'for', 'website orders paid by HitPay'),
      jsonb_build_object('m', '429P Stripe', 'c', '429p-two', 'mode', 'off', 'for', 'website orders'),
      jsonb_build_object('m', '429P HitPay Two', 'c', '429p-two', 'mode', 'off', 'for', 'website orders paid by HitPay'))
     and pg_temp.out('web_manager') = pg_temp.out('web_owner'),
  'web: each channel''s method, its HitPay method (or "HitPay (online)" when it names none) and its door methods; a door value that is not a method is left out');
select pg_temp.run(w, $q$select count(*) from public.payment_method_web_uses()$q$, '42501',
                   'web: ' || w || ' is refused')
  from unnest(array['staff', 'affiliate', 'anon']) w;

-- ── 6. Grants and the catalogue ──────────────────────────────────────────────
select pg_temp.check(has_function_privilege('authenticated', 'public.payment_method_web_uses()', 'execute')
                     and not has_function_privilege('anon', 'public.payment_method_web_uses()', 'execute')
                     and not exists (select 1 from pg_constraint c where c.conrelid = 'public.payment_methods'::regclass and c.contype = 'u')
                     and exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.indexname = 'payment_methods_live_name_key'
                                  and i.indexdef = 'CREATE UNIQUE INDEX payment_methods_live_name_key ON public.payment_methods USING btree (lower(btrim(name))) WHERE (deleted_at IS NULL)'),
  'catalogue: the website check is signed-in staff''s (it refuses others itself); one name rule, on live methods');

select pg_temp.check(true, 'payment-methods: all passed');
rollback;
