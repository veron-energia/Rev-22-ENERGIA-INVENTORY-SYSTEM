-- 548: the Class page for the four class vouchers (the Owner's answers of 27 Nov 2026), through the app's
-- own calls and REAL SIGN-INS (set local role authenticated / anon with each login's claims).
--
--   I  548 installs on production after 549 (fingerprint da952c4a.../1471), changes no existing function,
--      adds the ten; a second run changes nothing; grants (anon none, a login the page functions only, the
--      internal ones nobody); the tables' rules; every new owner-rights function searches pg_temp last.
--   N  The renames: three renamed, Lymphatic Class kept; prices and store prices unchanged; each rename in
--      the Audit Log (voucher_updated, old and new name); old invoice lines keep their printed names, also
--      one that had no snapshot (frozen first, its id in the Audit Log).
--   V  The Vouchers page's read (vouchers not in class_vouchers) excludes the four; the invoice form's read
--      of class_vouchers works for every staff role and not for anon.
--   S  The seed: Foundation 13 dates (12 sessions + graduation), Advanced 13, skin care 12 (Tue 28 Dec the
--      only Tuesday, the rest Wednesdays), Lymphatic Class none; capacity 6 for skin care alone.
--   B  Who bought: seats = line quantity; cancelled, refunded (whole and by line, partly), deleted and
--      draft invoices drop off; staff of store A see store A's buyers, staff of B theirs, Owner and Admin all (a Manager only their own store); an Inventory Manager, a former member of staff, a signed-in non-staff and anon are
--      refused; customer name and phone shown to staff.
--   C  A seat's one date: staff of the store choose it for their store's seats and are refused for the other
--      store's; the capacity of 6 per date (live seats only; a cancelled invoice frees its seats at once;
--      the trigger refuses a seventh whoever writes); Foundation and Advanced have no date to choose; the
--      Lymphatic Class has no limit; a date of another class is refused.
--   A  Attendance: staff tick their store's seats, not the other store's; a choose-a-date seat only on its
--      date; every session for Foundation; untick; a refunded or cancelled seat cannot be ticked; a date
--      with a tick cannot be changed.
--   E  Only Owners and Managers add, change or remove a date and edit details (staff, Admin, an Inventory
--      Manager, anon refused 42501); a date a seat chose cannot be removed; the capacity cannot go below
--      what a date holds; a login cannot write the tables directly.
--   L  v3 (the audit's finding): a class line corrected to another voucher by correct_invoice (Owner, and Staff of
--      the store; paid and unpaid) or changed by a direct update loses its seats' dates and ticks, with one Audit
--      Log entry each and the right "taken" count; a class line removed through the normal edit path writes its
--      entry; a voucher_id update of a non-class line, or one that leaves voucher_id as it is, does nothing; a
--      date is removed when only cancelled seats chose it (listed in the entry), refused when a live seat chose it
--      or anyone was ticked; the new function is nobody's but the server's; the two triggers are as said.
--   U  scripts/classes/undo-548.sql puts everything back exactly (functions, names, frozen snapshots,
--      tables); it refuses while staff recorded a seat's date or a tick; a second undo refuses; 548 again
--      makes the same.
--
-- Run on a copy of production after 549 that holds the four vouchers (the base has none, so this file makes
-- them as production has them: normal, unlimited, S$799, S$1,441, S$676, S$399):
--   psql -X -d <copy> -v ON_ERROR_STOP=1 -f scripts/classes/tests/class-page-548.sql
-- With -v skip_install=1 where 548 is in (I1-I2, N and U skipped). With -v mig=<file> another file than
-- supabase/548_*.sql (the mutation checks run a changed copy) and -v undo=<file> another undo. Every check runs, then the file fails if any
-- did. Everything is rolled back. Every name, phone and email is invented (+61 2 5550 ...., @example.invalid);
-- the repository is public.
\set ON_ERROR_STOP on
\if :{?mig}
\else
\set mig ../../../supabase/548_class_page_for_the_four_class_vouchers.sql
\endif
\if :{?undo}
\else
\set undo ../undo-548.sql
\endif
begin;
set local lock_timeout = '10s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise warning 'FAIL %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.fp() returns text language sql set search_path = public as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
-- Claims only (the caller stays the database owner): for the app's own calls that build fixtures.
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', case when key is null then 'anon' else 'authenticated' end, true),
          set_config('request.jwt.claims', '', true) $$;
-- A REAL sign-in: the login's claims and the database role the API gives it (authenticated, or anon for a
-- signed-out visitor), the statement run as that role, and the answer: 'ok:<text>' or 'ERR <sqlstate> <message>'.
-- Writes it makes stay when it returns ok, and are undone when it fails.
create function pg_temp.act(key text, q text) returns text language plpgsql as $f$
declare v text; s text; m text; r text := case when key is null or key = 'anon' then 'anon' else 'authenticated' end;
begin
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true);
  perform set_config('request.jwt.claim.role', r, true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(key), 'role', r)::text, true);
  begin
    execute 'set local role ' || r;
    execute q into v;
    execute 'reset role';
    return 'ok:' || coalesce(v, '');
  exception when others then
    get stacked diagnostics s = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR ' || s || ' ' || m;
  end;
end $f$;
create function pg_temp.okv(t text) returns text language sql as $$ select case when t like 'ok:%' then substr(t, 4) end $$;
create function pg_temp.refused(t text) returns boolean language sql as $$ select t like 'ERR 42501%' $$;

-- ═════ Fixtures (invented) ═════
do $$
declare u uuid; k text; st uuid; st2 uuid; v uuid; ph text;
  sfx text := lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
begin
  foreach k in array array['owner', 'manager', 'mgr_b', 'admin', 'staff_a', 'staff_b', 'im', 'former', 'nobody'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'c548-' || k || '-' || sfx || '@example.invalid');
    if k <> 'nobody' then
      insert into public.profiles(id, full_name, email, role, is_active)
        values (u, 'C548 ' || k, 'c548-' || k || '-' || sfx || '@example.invalid',
                (case k when 'staff_a' then 'staff' when 'staff_b' then 'staff' when 'former' then 'staff' when 'mgr_b' then 'manager'
                        when 'im' then 'inventory_manager' else k end)::public.user_role, k <> 'former');
    end if;
    insert into fx values (k, u);
  end loop;
  perform pg_temp.as_user('owner');
  insert into public.stores(name, code, country_code) values ('C548 Store A ' || sfx, 'C548A' || sfx, 'SG') returning id into st; insert into fx values ('storeA', st);
  insert into public.stores(name, code, country_code) values ('C548 Store B ' || sfx, 'C548B' || sfx, 'SG') returning id into st2; insert into fx values ('storeB', st2);
  insert into public.payment_methods(name, is_active) values ('C548 Cash ' || sfx, true) returning id into v; insert into fx values ('cash', v);
  insert into public.user_store_assignments(user_id, store_id) values
    (pg_temp.fx('manager'), st), (pg_temp.fx('staff_a'), st), (pg_temp.fx('former'), st), (pg_temp.fx('im'), st),
    (pg_temp.fx('staff_b'), st2), (pg_temp.fx('mgr_b'), st2);
  foreach k in array array['buyerA', 'buyerB', 'buyerC'] loop
    select '+6125550' || lpad(n::text, 4, '0') into ph from generate_series(1000, 9999) n
     where not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) = '+6125550' || lpad(n::text, 4, '0'))
     order by n limit 1;
    insert into public.customers(full_name, phone) values ('C548 ' || k, ph) returning id into v; insert into fx values (k, v);
  end loop;
  -- The four vouchers as production has them (normal, unlimited, no expiry), unless the copy has them.
  if not exists (select 1 from public.vouchers where code = 'EmiLymphatic' and deleted_at is null) then
    insert into public.vouchers(name, code, selling_price) values
      ('Emi Foundation Lymphatic Zoom Class', 'EmiLymphatic', 799), ('Emi Advanced Lymphatic Zoom Class', 'AdvancedZoom', 1441),
      ('K Pop Facial Class', 'KPopClass', 676), ('Lymphatic Class', 'L-C', 399);
  end if;
  insert into public.vouchers(name, code, selling_price) values ('C548 Ordinary Voucher ' || sfx, 'C548V' || sfx, 50) returning id into v;
  insert into fx values ('ordinary', v);
  insert into fx select 'v_' || x.code, x.id from public.vouchers x where x.code in ('EmiLymphatic', 'AdvancedZoom', 'KPopClass', 'L-C') and x.deleted_at is null;
  insert into public.voucher_store_prices(voucher_id, store_id, selling_price)
    select vv.id, ss.id, vv.selling_price from public.vouchers vv, public.stores ss
     where vv.id in (select v2 from (select pg_temp.fx('v_EmiLymphatic') v2 union select pg_temp.fx('v_AdvancedZoom') union select pg_temp.fx('v_KPopClass')
                                      union select pg_temp.fx('v_L-C') union select pg_temp.fx('ordinary')) q)
       and ss.id in (pg_temp.fx('storeA'), pg_temp.fx('storeB'))
    on conflict (voucher_id, store_id) do nothing;
end $$;
create function pg_temp.vl(code text, qty int default 1) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('v_' || code), 'quantity', qty) $$;
create function pg_temp.mk(store text, buyer text, items jsonb) returns uuid language plpgsql as
$$begin perform pg_temp.as_user('owner');
  return public.create_invoice_with_details(pg_temp.fx(store), pg_temp.fx(buyer), items,
            jsonb_build_object('business_date', public.sg_today()::text)); end$$;
create function pg_temp.pay(inv uuid) returns void language plpgsql as
$$begin perform pg_temp.as_user('owner');
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
     'amount', public.invoice_charge_total(inv) - public.invoice_net_received(inv)))); end$$;
create function pg_temp.line_of(inv uuid, code text) returns uuid language sql as
$$ select id from public.invoice_items where invoice_id = inv and line_kind = 'voucher' and voucher_id = pg_temp.fx('v_' || code) limit 1 $$;
create function pg_temp.cancel(inv uuid) returns text language plpgsql as
$$begin perform pg_temp.as_user('owner');
  return pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, %L)', inv, 'Customer changed mind', gen_random_uuid())); end$$;
-- A refund of units of a paid voucher line: the benefit allocation of its issued voucher row, as the guided refund sends it.
create function pg_temp.refund_units(inv uuid, line uuid, units int) returns text language plpgsql as
$$declare b record; a numeric; pay uuid;
begin
  perform pg_temp.as_user('owner');
  select bv.* into b from public.invoice_benefit_values bv where bv.invoice_item_id = line and bv.reward_voucher_id is not null order by bv.id limit 1;
  if b.id is null then return 'no benefit row'; end if;
  a := round(units * b.paid_value / b.granted_value, 2);
  select p.id into pay from public.invoice_payments p where p.invoice_id = inv and p.entry_kind <> 'correction_reversal' order by p.created_at limit 1;
  return pg_temp.err(format('select public.refund_invoice_recorded(%L, %L::jsonb, %L::jsonb, %L::jsonb, %L, %L)', inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', line, 'amount', a, 'benefits', jsonb_build_array(jsonb_build_object('benefit_id', b.id, 'amount', a)))),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', a)), '[]', 'Refund check', gen_random_uuid()));
end$$;
-- Page data as someone, parsed.
create function pg_temp.page(who text) returns jsonb language plpgsql as
$$declare t text; begin t := pg_temp.act(who, 'select public.class_page_data()::text'); return case when t like 'ok:%' then substr(t, 4)::jsonb end; end$$;
create function pg_temp.seats_of(who text, code text) returns int language sql as
$$ select coalesce(jsonb_array_length(coalesce((select jsonb_agg(s) from jsonb_array_elements(pg_temp.page(who)->'seats') s
    where (s->>'voucher_id')::uuid = pg_temp.fx('v_' || code)), '[]')), 0) $$;
create function pg_temp.session_id(code text, d date) returns uuid language plpgsql as
$$ begin return (select id from public.class_sessions where voucher_id = pg_temp.fx('v_' || code) and session_date = d); end $$;
create function pg_temp.taken(who text, code text, d date) returns int language sql as
$$ select (s->>'taken')::int from jsonb_array_elements(pg_temp.page(who)->'classes') c, jsonb_array_elements(c->'sessions') s
    where (c->>'voucher_id')::uuid = pg_temp.fx('v_' || code) and (s->>'session_date')::date = d $$;
create function pg_temp.choose(who text, line uuid, seat int, sess uuid) returns text language sql as
$$ select pg_temp.act(who, format('select public.class_choose_date(%L, %s, %L)::text', line, seat, sess)) $$;
create function pg_temp.tick(who text, sess uuid, line uuid, seat int, att boolean default true) returns text language sql as
$$ select pg_temp.act(who, format('select public.class_set_attendance(%L, %L, %s, %L)::text', sess, line, seat, att)) $$;
create function pg_temp.ticks(line uuid) returns int language plpgsql as $$ begin return (select count(*)::int from public.class_attendance where invoice_item_id = line); end $$;
create function pg_temp.dates(line uuid) returns int language plpgsql as $$ begin return (select count(*)::int from public.class_seat_dates where invoice_item_id = line); end $$;

-- Before 548: what it must not change.
create temp table fn0 as select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as def
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
create temp table tg0 as select t.tgname, pg_get_triggerdef(t.oid) as def from pg_trigger t
  where t.tgrelid = 'public.invoice_items'::regclass and not t.tgisinternal;
create temp table pr0 as select v.code, v.name, v.selling_price,
    (select md5(coalesce(string_agg(s.store_id::text || ':' || s.selling_price::text, ',' order by s.store_id), ''))
       from public.voucher_store_prices s where s.voucher_id = v.id) as sp
  from public.vouchers v where v.code in ('EmiLymphatic', 'AdvancedZoom', 'KPopClass', 'L-C') and v.deleted_at is null;
select to_regclass('public.class_vouchers') is not null as had548 \gset
select pg_temp.fp() as fp_before \gset
\if :had548
\if :{?skip_install}
\set mode skip
\else
\echo 548 is already in: run with -v skip_install=1
select 1/0;
\endif
\else
\if :{?skip_install}
\echo 548 is not in: run without -v skip_install
select 1/0;
\endif
\set mode install
\endif
select :'mode' = 'install' as by_us \gset

-- Invoices sold BEFORE 548 (install mode): Foundation under its old name, one line with no printed name of
-- its own (frozen by 548 before the rename), one with.
\if :by_us
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('EmiLymphatic', 1))) as old1 \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('EmiLymphatic', 1))) as old2 \gset
select pg_temp.line_of(:'old1', 'EmiLymphatic') as old1_line \gset
select pg_temp.line_of(:'old2', 'EmiLymphatic') as old2_line \gset
update public.invoice_items set item_name_snapshot = null where id = :'old2_line';
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 1))) as old3 \gset
select pg_temp.line_of(:'old3', 'KPopClass') as old3_line \gset
-- Production's shapes (read on 28 Nov): Lymphatic Class lines, one with no printed name and one with; a Foundation
-- line whose printed name is an OLDER name; (the skin care line above has its name). Sold before 548 is in.
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('L-C', 1))) as oldlc1 \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('L-C', 1))) as oldlc2 \gset
select pg_temp.line_of(:'oldlc1', 'L-C') as oldlc1_line, pg_temp.line_of(:'oldlc2', 'L-C') as oldlc2_line \gset
update public.invoice_items set item_name_snapshot = null where id = :'oldlc1_line';
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('EmiLymphatic', 1))) as oldem \gset
select pg_temp.line_of(:'oldem', 'EmiLymphatic') as oldem_line \gset
update public.invoice_items set item_name_snapshot = 'Emi Lymphatic Zoom Class' where id = :'oldem_line';
select (select item_name_snapshot from public.invoice_items where id = :'old1_line') as old1_snap_before \gset
select (select item_name_snapshot from public.invoice_items where id = :'old2_line') is null as old2_null_before \gset
\endif

-- ═════ I Install ═════
\if :by_us
\ir :mig
select pg_temp.check(pg_temp.fp() <> :'fp_before', 'I1 548 changed the function set (only by adding)');
select pg_temp.check((select count(*) from fn0 a join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as def
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') b using (fn) where a.def <> b.def) = 0,
  'I1 no existing function changed (every one of the 1,471 has its text as before)');
select pg_temp.check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f') = (select count(*) from fn0) + 10,
  'I1 exactly ten functions added');
select pg_temp.fp() as fp_after \gset
\ir :mig
select pg_temp.check(pg_temp.fp() = :'fp_after', 'I2 a second run changes nothing');
\endif

select pg_temp.check((select count(*) from pg_class where relnamespace = 'public'::regnamespace and relname like 'class\_%' and relkind = 'r' and relrowsecurity) = 4,
  'I3 the four tables have row-level security');
select pg_temp.check(not has_table_privilege('anon', 'public.class_vouchers', 'select') and not has_table_privilege('anon', 'public.class_sessions', 'select')
  and not has_table_privilege('anon', 'public.class_seat_dates', 'select') and not has_table_privilege('anon', 'public.class_attendance', 'select'),
  'I3 anon reads none of the tables');
select pg_temp.check(not exists (select 1 from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname like 'class\_%' and c.relkind = 'r'
    and (has_table_privilege('authenticated', c.oid, 'insert,update,delete,truncate,references,trigger') or not has_table_privilege('authenticated', c.oid, 'select'))),
  'I3 a login only reads the tables (no insert, update, delete, truncate, references or trigger)');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('class_line_units', 'class_live_seats', 'trg_class_seat_date_capacity', 'trg_class_line_changed')
    and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
  'I4 the internal functions are nobody''s but the server''s');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('class_page_data', 'class_choose_date', 'class_set_attendance', 'class_save_session', 'class_remove_session', 'class_save_details')
    and (has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute'))),
  'I4 the six page functions: signed-in logins yes, anon no');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
    and (p.proname like 'class\_%' or p.proname = 'trg_class_seat_date_capacity')
    and not (p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig))), 'I5 every new owner-rights function searches pg_temp last (546''s rule)');

-- ═════ N Renames ═════
select pg_temp.check((select string_agg(v.code || '=' || v.name, '; ' order by v.code) from public.vouchers v
   where v.code in ('EmiLymphatic', 'AdvancedZoom', 'KPopClass', 'L-C') and v.deleted_at is null)
   = 'AdvancedZoom=Lymphatic Advanced Workshop 2027; EmiLymphatic=Lymphatic Foundation Workshop 2027; KPopClass=Korea No.1 Skin Care Workshop; L-C=Lymphatic Class',
  'N1 the three are renamed, Lymphatic Class keeps its name');
select pg_temp.check(not exists (select 1 from pr0 b join public.vouchers v on v.code = b.code and v.deleted_at is null
     where v.selling_price <> b.selling_price
        or (select md5(coalesce(string_agg(s.store_id::text || ':' || s.selling_price::text, ',' order by s.store_id), ''))
              from public.voucher_store_prices s where s.voucher_id = v.id) <> b.sp)
  and (select count(*) from pr0) = 4, 'N2 prices (S$799, 1,441, 676, 399) and every store''s price are as before');
\if :by_us
select pg_temp.check((select count(*) from public.audit_logs a where a.table_name = 'vouchers' and a.action = 'voucher_updated'
        and a.record_id in (pg_temp.fx('v_EmiLymphatic'), pg_temp.fx('v_AdvancedZoom'), pg_temp.fx('v_KPopClass'))
        and a.old_data ? 'name' and a.new_data ? 'name') = 3
   and not exists (select 1 from public.audit_logs a where a.table_name = 'vouchers' and a.record_id = pg_temp.fx('v_L-C') and a.action = 'voucher_updated'),
  'N3 each rename is in the Audit Log (voucher_updated, the old and the new name); Lymphatic Class has none');
select pg_temp.check((select (a.old_data->>'name') || ' -> ' || (a.new_data->>'name') from public.audit_logs a where a.table_name = 'vouchers' and a.action = 'voucher_updated'
        and a.record_id = pg_temp.fx('v_KPopClass')) = 'K Pop Facial Class -> Korea No.1 Skin Care Workshop', 'N3 the entry says old -> new');
-- Old invoices keep their names: what the invoice prints (invoice_display_names' line name) is the old name, also for the line that had no snapshot.
select pg_temp.as_user('owner');
select pg_temp.check((select (public.invoice_display_names(:'old1'::uuid)->'lines')->>:'old1_line') = 'Emi Foundation Lymphatic Zoom Class',
  'N4 an old Foundation invoice still prints "Emi Foundation Lymphatic Zoom Class"');
select pg_temp.check((select (public.invoice_display_names(:'old2'::uuid)->'lines')->>:'old2_line') = 'Emi Foundation Lymphatic Zoom Class'
  and (select item_name_snapshot from public.invoice_items where id = :'old2_line') = 'Emi Foundation Lymphatic Zoom Class' and :'old2_null_before'::boolean,
  'N4 the line that had no printed name of its own was frozen at the old name before the rename');
select pg_temp.check((select item_name_snapshot from public.invoice_items where id = :'old3_line') = 'K Pop Facial Class'
  and (select (public.invoice_display_names(inv.invoice_id)->'lines')->>(:'old3_line') from public.invoice_items inv where inv.id = :'old3_line') = 'K Pop Facial Class',
  'N4 an old skin care invoice still prints "K Pop Facial Class"');
select pg_temp.check((select item_name_snapshot from public.invoice_items where id = :'old1_line') = :'old1_snap_before', 'N4 a line that had its name is untouched');
-- Production-shaped lines (the apply of 28 Nov stopped on the Lymphatic Class's unnamed lines).
select pg_temp.check((select item_name_snapshot from public.invoice_items where id = :'oldlc1_line') is null
   and (select (public.invoice_display_names(:'oldlc1'::uuid)->'lines')->>:'oldlc1_line') = 'Lymphatic Class'
   and (select item_name_snapshot from public.invoice_items where id = :'oldlc2_line') = 'Lymphatic Class',
  'N7 a Lymphatic Class line with no printed name is LEFT as it is (still none) and prints "Lymphatic Class"; the one with its name is as it was');
select pg_temp.check(not exists (select 1 from public.audit_logs a where a.action = 'class_lines_name_frozen' and a.record_id = pg_temp.fx('v_L-C')),
  'N7b nothing was frozen for the Lymphatic Class (its name does not change): no class_lines_name_frozen entry');
select pg_temp.check((select item_name_snapshot from public.invoice_items where id = :'oldem_line') = 'Emi Lymphatic Zoom Class'
   and (select (public.invoice_display_names(:'oldem'::uuid)->'lines')->>:'oldem_line') = 'Emi Lymphatic Zoom Class'
   and not exists (select 1 from public.audit_logs a where a.action = 'class_lines_name_frozen' and a.new_data->'invoice_item_ids' @> to_jsonb(array[:'oldem_line']::text[])),
  'N8 a Foundation line whose printed name is an OLDER name keeps it, and is not in the frozen list');
select pg_temp.check((select count(*) from public.audit_logs a where a.action = 'class_lines_name_frozen' and a.record_id = pg_temp.fx('v_EmiLymphatic')
        and a.new_data->'invoice_item_ids' @> to_jsonb(array[:'old2_line']::text[]) and jsonb_array_length(a.new_data->'invoice_item_ids') = 1) = 1
   and (select item_name_snapshot from public.invoice_items where id = :'old2_line') = 'Emi Foundation Lymphatic Zoom Class',
  'N9 the Foundation line with no printed name is frozen to "Emi Foundation Lymphatic Zoom Class" and is the only one listed');
select pg_temp.check((select count(*) from public.audit_logs a where a.action = 'class_lines_name_frozen' and a.record_id = pg_temp.fx('v_EmiLymphatic')
        and a.new_data->'invoice_item_ids' @> to_jsonb(array[:'old2_line']::text[])) = 1, 'N5 the frozen line is named in one Audit Log entry (the UNDO reads it)');
-- A NEW sale after the rename prints the new name.
select pg_temp.line_of(pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('EmiLymphatic', 1))), 'EmiLymphatic') as new1_line \gset
select pg_temp.check((select item_name_snapshot from public.invoice_items where id = :'new1_line') = 'Lymphatic Foundation Workshop 2027', 'N6 a sale made after prints the new name');
\endif

-- (The old skin care sale is cancelled: the seat counts below are the fixtures' own.)
\if :by_us
select pg_temp.cancel(:'old3') as old3_cancelled \gset
select pg_temp.cancel(:'oldlc1') as oldlc1_cancelled, pg_temp.cancel(:'oldlc2') as oldlc2_cancelled, pg_temp.cancel(:'oldem') as oldem_cancelled \gset
\endif

-- ═════ V The Vouchers page and the invoice form read the class table ═════
select pg_temp.check(pg_temp.okv(pg_temp.act('owner', $q$select string_agg(v.name, ';' order by v.name) from public.vouchers v
    where v.deleted_at is null and v.id not in (select c.voucher_id from public.class_vouchers c) and v.code like 'C548V%'$q$)) like 'C548 Ordinary Voucher%',
  'V1 the Vouchers page''s read (every voucher not a class) still lists an ordinary voucher');
select pg_temp.check(pg_temp.okv(pg_temp.act('owner', $q$select count(*)::text from public.vouchers v
    where v.deleted_at is null and v.id not in (select c.voucher_id from public.class_vouchers c)
      and v.code in ('EmiLymphatic', 'AdvancedZoom', 'KPopClass', 'L-C')$q$)) = '0', 'V2 the Vouchers page''s read excludes the four class vouchers');
select pg_temp.check(pg_temp.okv(pg_temp.act('owner', $q$select count(*)::text from public.class_vouchers$q$)) = '4'
  and pg_temp.okv(pg_temp.act('staff_a', $q$select count(*)::text from public.class_vouchers$q$)) = '4'
  and pg_temp.okv(pg_temp.act('im', $q$select count(*)::text from public.class_vouchers$q$)) = '4'
  and pg_temp.okv(pg_temp.act('nobody', $q$select count(*)::text from public.class_vouchers$q$)) = '0'
  and pg_temp.act(null, $q$select count(*)::text from public.class_vouchers$q$) like 'ERR 42501%',
  'V3 the invoice form''s read of class_vouchers: every staff role sees the four; a signed-in non-staff none; anon refused');

-- ═════ S Seed ═════
select pg_temp.check((select count(*) from public.class_sessions where voucher_id = pg_temp.fx('v_EmiLymphatic')) = 13
  and (select count(*) from public.class_sessions where voucher_id = pg_temp.fx('v_AdvancedZoom')) = 13
  and (select count(*) from public.class_sessions where voucher_id = pg_temp.fx('v_KPopClass')) = 12
  and (select count(*) from public.class_sessions where voucher_id = pg_temp.fx('v_L-C')) = 0, 'S1 dates: 13, 13, 12 and none for the Lymphatic Class');
select pg_temp.check((select string_agg(session_date::text, ' ' order by session_date) from public.class_sessions where voucher_id = pg_temp.fx('v_EmiLymphatic'))
  = '2027-01-29 2027-02-26 2027-03-26 2027-04-30 2027-05-28 2027-06-25 2027-07-30 2027-08-27 2027-09-24 2027-10-29 2027-11-26 2027-12-30 2028-01-01',
  'S2 Foundation: Fri 29 Jan to Fri 29 Oct, Fri 26 Nov, Thu 30 Dec, graduation Sat 1 Jan 2028');
select pg_temp.check((select string_agg(session_date::text, ' ' order by session_date) from public.class_sessions where voucher_id = pg_temp.fx('v_AdvancedZoom'))
  = '2027-01-28 2027-02-25 2027-03-25 2027-04-29 2027-05-27 2027-06-24 2027-07-29 2027-08-26 2027-09-23 2027-10-28 2027-11-25 2027-12-29 2028-01-01',
  'S3 Advanced: Thu 28 Jan to Thu 28 Oct, Thu 25 Nov, Wed 29 Dec, graduation Sat 1 Jan 2028');
select pg_temp.check((select string_agg(session_date::text, ' ' order by session_date) from public.class_sessions where voucher_id = pg_temp.fx('v_KPopClass'))
  = '2027-01-27 2027-02-24 2027-03-24 2027-04-28 2027-05-26 2027-06-23 2027-07-28 2027-08-25 2027-09-22 2027-10-27 2027-11-24 2027-12-28'
  and (select count(*) from public.class_sessions where voucher_id = pg_temp.fx('v_KPopClass') and extract(dow from session_date) = 3) = 11
  and (select extract(dow from session_date) from public.class_sessions where voucher_id = pg_temp.fx('v_KPopClass') and session_date = '2027-12-28') = 2,
  'S4 skin care: 12 dates, Wednesdays and Tue 28 Dec');
select pg_temp.check((select count(*) from public.class_sessions s where s.voucher_id in (pg_temp.fx('v_EmiLymphatic'), pg_temp.fx('v_AdvancedZoom'))
    and s.kind = 'graduation' and s.session_date = '2028-01-01' and s.starts_at = '10:00' and s.ends_at = '15:00' and s.mode = 'in_person') = 2
  and (select count(*) from public.class_sessions s where s.voucher_id in (pg_temp.fx('v_EmiLymphatic'), pg_temp.fx('v_AdvancedZoom')) and s.must_attend and s.mode = 'in_person') = 2
  and (select count(*) from public.class_sessions s where s.kind = 'revision' and s.mode = 'zoom') = 4
  and (select count(*) from public.class_sessions s where s.voucher_id = pg_temp.fx('v_KPopClass') and s.starts_at = '19:00' and s.ends_at = '21:00' and s.mode = 'in_person'
        and s.venue = 'The Adelphi, 1 Coleman Street #B1-37') = 12,
  'S5 the posters'' times and places: graduation 10:00-15:00 in person, the first session in person and must-attend, 4 revision sessions on Zoom, skin care 7-9 PM at The Adelphi');
select pg_temp.check((select string_agg(v.code || '=' || c.seat_mode || '/' || coalesce(c.capacity_per_date::text, '-'), ' ' order by v.code)
    from public.class_vouchers c join public.vouchers v on v.id = c.voucher_id) = 'AdvancedZoom=all_sessions/- EmiLymphatic=all_sessions/- KPopClass=choose_date/6 L-C=choose_date/-',
  'S6 seat modes and capacity: skin care chooses one date, 6 per date; the Lymphatic Class chooses one day, no limit; the two workshops attend every session');
select pg_temp.check(not exists (select 1 from public.class_vouchers where details::text ~* '@|\+61|[0-9]{8}'), 'S7 no personal data in the details');

-- ═════ Sales for B, C, A ═════
-- Store A: buyerA 3 skin care (paid), buyerA 3 skin care (unpaid), 2 Foundation (paid), 2 Lymphatic Class.
-- Store B: buyerB 1 skin care + 1 Foundation, buyerC 2 skin care.
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 3))) as a_skin1 \gset
select pg_temp.pay(:'a_skin1');
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 3))) as a_skin2 \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('EmiLymphatic', 2))) as a_found \gset
select pg_temp.pay(:'a_found');
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('L-C', 2))) as a_lc \gset
select pg_temp.mk('storeB', 'buyerB', jsonb_build_array(pg_temp.vl('KPopClass', 1), pg_temp.vl('EmiLymphatic', 1))) as b_mix \gset
select pg_temp.mk('storeB', 'buyerC', jsonb_build_array(pg_temp.vl('KPopClass', 2))) as b_skin \gset
select pg_temp.line_of(:'a_skin1', 'KPopClass') as l_a_skin1, pg_temp.line_of(:'a_skin2', 'KPopClass') as l_a_skin2,
       pg_temp.line_of(:'a_found', 'EmiLymphatic') as l_a_found, pg_temp.line_of(:'a_lc', 'L-C') as l_a_lc,
       pg_temp.line_of(:'b_mix', 'KPopClass') as l_b_skin1, pg_temp.line_of(:'b_mix', 'EmiLymphatic') as l_b_found,
       pg_temp.line_of(:'b_skin', 'KPopClass') as l_b_skin2 \gset

-- ═════ B Who bought ═════
-- Seats so far: skin care A 6 + B 3 = 9; Foundation: 2 old + 1 new (A) + 2 + 1 = 6 (the 2 old and the new one are store A's, buyerA, 1 each);
-- counted from the fixtures: skin care = 3+3 (A) and 1+2 (B); Foundation (A) = 1 old1 + 1 old2 + 1 new + 2 = 5, (B) 1; Lymphatic Class (A) 2.
select pg_temp.check(pg_temp.seats_of('owner', 'KPopClass') = 9 and pg_temp.seats_of('admin', 'KPopClass') = 9,
  'B1 Owner and Admin (every store, by the app''s store access) see all skin care seats (6 at A, 3 at B)');
select pg_temp.check(pg_temp.seats_of('manager', 'KPopClass') = 6 and pg_temp.seats_of('mgr_b', 'KPopClass') = 3,
  'B1b a Manager sees only their own store''s seats: the Manager of store A 6, the Manager of store B 3');
select pg_temp.check(pg_temp.seats_of('staff_a', 'KPopClass') = 6 and pg_temp.seats_of('staff_b', 'KPopClass') = 3,
  'B2 staff of store A see store A''s 6 seats and not store B''s; staff of store B see their 3');
create function pg_temp.expected(code text, store text) returns int language sql as
$$ select coalesce(sum(it.quantity), 0)::int from public.invoice_items it join public.invoices i on i.id = it.invoice_id
    where it.line_kind = 'voucher' and it.voucher_id = pg_temp.fx('v_' || code) and i.deleted_at is null
      and i.status not in ('cancelled', 'refunded', 'draft') and (store is null or i.store_id = pg_temp.fx(store)) $$;
select pg_temp.check(pg_temp.seats_of('manager', 'EmiLymphatic') = pg_temp.expected('EmiLymphatic', 'storeA')
   and pg_temp.seats_of('mgr_b', 'EmiLymphatic') = pg_temp.expected('EmiLymphatic', 'storeB'), 'B3b a Manager sees their store''s Foundation seats only');
select pg_temp.check(pg_temp.seats_of('staff_a', 'EmiLymphatic') = pg_temp.expected('EmiLymphatic', 'storeA')
   and pg_temp.seats_of('staff_b', 'EmiLymphatic') = pg_temp.expected('EmiLymphatic', 'storeB')
   and pg_temp.seats_of('owner', 'EmiLymphatic') = pg_temp.expected('EmiLymphatic', null)
   and pg_temp.seats_of('staff_a', 'L-C') = 2 and pg_temp.seats_of('staff_b', 'L-C') = 0,
  'B3 Foundation and Lymphatic Class seats follow the same rule per store (line quantity on live invoices)');
select pg_temp.check((select string_agg(distinct s->>'customer_name', ',') from jsonb_array_elements(pg_temp.page('staff_b')->'seats') s) like 'C548 buyer%'
   and (select count(*) from jsonb_array_elements(pg_temp.page('staff_b')->'seats') s where s->>'customer_phone' ~ '^\+6125550') > 0
   and not exists (select 1 from jsonb_array_elements(pg_temp.page('staff_b')->'seats') s where s->>'customer_name' = 'C548 buyerA'),
  'B4 staff see the buyer''s name and phone (as the Invoices page shows them), only of their own store''s invoices');
select pg_temp.check((select s->>'invoice_no' from jsonb_array_elements(pg_temp.page('staff_a')->'seats') s where (s->>'invoice_item_id')::uuid = :'l_a_skin2'::uuid and (s->>'seat_no')::int = 3)
     = (select invoice_no from public.invoices where id = :'a_skin2')
   and (select s->>'invoice_status' from jsonb_array_elements(pg_temp.page('staff_a')->'seats') s where (s->>'invoice_item_id')::uuid = :'l_a_skin2'::uuid limit 1) = 'unpaid'
   and (select (s->>'seats_on_line')::int from jsonb_array_elements(pg_temp.page('staff_a')->'seats') s where (s->>'invoice_item_id')::uuid = :'l_a_skin2'::uuid limit 1) = 3,
  'B5 an unpaid invoice''s seats count too, shown with the invoice number and status, "seat n of 3"');
select pg_temp.check(pg_temp.page('staff_a')->>'can_edit' = 'false' and pg_temp.page('manager')->>'can_edit' = 'true' and pg_temp.page('owner')->>'can_edit' = 'true'
   and pg_temp.page('admin')->>'can_edit' = 'false', 'B6 can_edit: Owner and Manager yes; staff and Admin no');
select pg_temp.check(pg_temp.act('im', 'select public.class_page_data()::text') like 'ERR 42501%Inventory Manager%'
   and pg_temp.refused(pg_temp.act('former', 'select public.class_page_data()::text'))
   and pg_temp.refused(pg_temp.act('nobody', 'select public.class_page_data()::text'))
   and pg_temp.refused(pg_temp.act(null, 'select public.class_page_data()::text')),
  'B7 an Inventory Manager, a former member of staff, a signed-in non-staff and anon are refused the page');
select pg_temp.check((select (s->>'seats_sold')::int from jsonb_array_elements(pg_temp.page('staff_a')->'classes') s where (s->>'voucher_id')::uuid = pg_temp.fx('v_KPopClass')) = 9,
  'B8 seats sold (a count, no customer) is across all stores');
-- Refunds, cancellation, deletion, draft: seats drop off.
select pg_temp.check(pg_temp.okv(pg_temp.act('owner', format('select public.class_line_units(%L)::text', :'l_a_skin1'))) is null, 'B9 class_line_units is not callable by a login');
select pg_temp.check((select public.class_line_units(:'l_a_skin1'::uuid)) = 3 and (select public.class_line_units(:'l_a_skin2'::uuid)) = 3, 'B9 a line''s seats = its quantity (3, 3)');
select pg_temp.check(pg_temp.refund_units(:'a_skin1', :'l_a_skin1', 1) = 'ok', 'B10 one unit of the 3 refunded by line (fixture)');
select pg_temp.check((select public.class_line_units(:'l_a_skin1'::uuid)) = 2 and pg_temp.seats_of('owner', 'KPopClass') = 8,
  'B10 one unit refunded by line: 2 seats left on the line, 8 in all');
select pg_temp.refund_units(:'a_skin1', :'l_a_skin1', 2) as r11 \gset
select pg_temp.check(:'r11' = 'ok' and (select public.class_line_units(:'l_a_skin1'::uuid)) = 0 and pg_temp.seats_of('owner', 'KPopClass') = 6,
  'B11 the rest refunded: no seat is left on the line (6 in all)');
select pg_temp.cancel(:'a_skin2') as r12 \gset
select pg_temp.check(:'r12' = 'ok' and (select public.class_line_units(:'l_a_skin2'::uuid)) = 0 and pg_temp.seats_of('owner', 'KPopClass') = 3,
  'B12 a cancelled invoice gives no seats (3 left, store B''s)');
select pg_temp.check(pg_temp.seats_of('staff_a', 'KPopClass') = 0, 'B12 staff of A now see none for skin care');
update public.invoices set status = 'draft' where id = :'b_skin';
select pg_temp.check((select public.class_line_units(:'l_b_skin2'::uuid)) = 0 and pg_temp.seats_of('owner', 'KPopClass') = 1, 'B13 a draft gives no seats');
update public.invoices set status = 'unpaid' where id = :'b_skin';
update public.invoices set deleted_at = now() where id = :'b_skin';
select pg_temp.check((select public.class_line_units(:'l_b_skin2'::uuid)) = 0 and pg_temp.seats_of('owner', 'KPopClass') = 1, 'B14 a deleted invoice gives no seats');
update public.invoices set deleted_at = null where id = :'b_skin';
select pg_temp.check((select public.class_line_units(:'l_b_skin2'::uuid)) = 2 and pg_temp.seats_of('owner', 'KPopClass') = 3, 'B15 restored (fixture): its 2 seats are back');
update public.invoices set status = 'refunded' where id = :'b_skin';
select pg_temp.check((select public.class_line_units(:'l_b_skin2'::uuid)) = 0, 'B16 a refunded invoice gives no seats');
update public.invoices set status = 'unpaid' where id = :'b_skin';

-- Seats now (skin care): B 3 (l_b_skin1: 1 seat, l_b_skin2: 2 seats). Make more at A for the capacity of 6.
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 3))) as a_skin3 \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 3))) as a_skin4 \gset
select pg_temp.line_of(:'a_skin3', 'KPopClass') as l_a_skin3, pg_temp.line_of(:'a_skin4', 'KPopClass') as l_a_skin4 \gset
select pg_temp.session_id('KPopClass', '2027-03-24') as sk_mar \gset
select pg_temp.session_id('KPopClass', '2027-04-28') as sk_apr \gset

-- ═════ C A seat's one date ═════
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_a', :'l_a_skin3', 1, :'sk_mar')) like '%"changed": true%', 'C1 staff of store A choose a date for a store A seat');
select pg_temp.check(pg_temp.refused(pg_temp.choose('staff_a', :'l_b_skin1', 1, :'sk_mar')), 'C2 staff of store A cannot choose a date for a store B seat (42501)');
select pg_temp.check(pg_temp.refused(pg_temp.choose('staff_b', :'l_a_skin3', 2, :'sk_mar')), 'C2 staff of store B cannot choose for a store A seat');
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_b', :'l_b_skin1', 1, :'sk_mar')) like '%"changed": true%', 'C3 staff of store B choose for their own');
select pg_temp.check(pg_temp.okv(pg_temp.choose('manager', :'l_a_skin3', 2, :'sk_mar')) like '%"changed": true%'
   and pg_temp.okv(pg_temp.choose('owner', :'l_a_skin3', 3, :'sk_mar')) like '%"changed": true%'
   and pg_temp.okv(pg_temp.choose('admin', :'l_a_skin4', 1, :'sk_mar')) like '%"changed": true%', 'C4 the Manager of store A, an Owner and an Admin choose for store A''s seats: 5 seats on 24 Mar');
select pg_temp.check(pg_temp.refused(pg_temp.choose('manager', :'l_b_skin2', 2, :'sk_mar')) and pg_temp.refused(pg_temp.choose('mgr_b', :'l_a_skin3', 2, :'sk_mar')),
  'C4b a Manager cannot choose a date for another store''s seat (42501), either way round');
select pg_temp.check(pg_temp.taken('staff_a', 'KPopClass', '2027-03-24') = 5, 'C5 the date shows 5 seats taken (all stores) to a member of staff');
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_a', :'l_a_skin4', 2, :'sk_mar')) like '%"changed": true%', 'C6 the sixth seat fits (6 of 6)');
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_skin4', 3, :'sk_mar') like 'ERR 23514%full: 6 of 6%', 'C7 the seventh is refused: that date is full (6 of 6)');
select pg_temp.check(pg_temp.choose('owner', :'l_b_skin2', 1, :'sk_mar') like 'ERR 23514%full%', 'C7 an Owner cannot overfill it either');
select pg_temp.check(pg_temp.err(format('insert into public.class_seat_dates(invoice_item_id, seat_no, session_id) values (%L, 3, %L)', :'l_a_skin4', :'sk_mar')) like '%full%',
  'C8 the table''s own trigger refuses a seventh from any writer (direct insert as the database owner)');
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_a', :'l_a_skin4', 3, :'sk_apr')) like '%"changed": true%', 'C9 another date has its own 6 places');
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_a', :'l_a_skin4', 3, :'sk_mar')) is null, 'C9 moving that seat back to March is refused while March is full');
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_a', :'l_a_skin4', 3, null)) like '%"changed": true%' and pg_temp.dates(:'l_a_skin4') = 2, 'C10 a date can be cleared');
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_a', :'l_a_skin4', 3, :'sk_mar')) is null and pg_temp.taken('owner', 'KPopClass', '2027-03-24') = 6, 'C10 March is still full: 6 of 6');
-- A cancelled invoice frees its places at once; a refunded unit too.
select pg_temp.check(pg_temp.cancel(:'a_skin4') = 'ok' and pg_temp.taken('owner', 'KPopClass', '2027-03-24') = 4, 'C11 cancelling an invoice frees its seats at once (6 of 6 -> 4)');
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_b', :'l_b_skin2', 1, :'sk_mar')) like '%"changed": true%'
   and pg_temp.okv(pg_temp.choose('staff_b', :'l_b_skin2', 2, :'sk_mar')) like '%"changed": true%' and pg_temp.taken('owner', 'KPopClass', '2027-03-24') = 6,
  'C12 and the freed places can be taken: 6 of 6 again');
select pg_temp.check(pg_temp.choose('staff_b', :'l_b_skin2', 1, null) like 'ok:%' and pg_temp.taken('owner', 'KPopClass', '2027-03-24') = 5, 'C13 cleared: 5');
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_skin3', 1, :'sk_apr') like 'ok:%' and pg_temp.taken('owner', 'KPopClass', '2027-04-28') = 1
   and pg_temp.taken('owner', 'KPopClass', '2027-03-24') = 4, 'C14 a seat moves to another date (no tick yet): March 4, April 1');
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_skin3', 1, :'sk_apr') like '%"changed": false%', 'C15 the same date again changes nothing');
-- Wrong class, wrong class mode, wrong seat.
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_skin3', 1, pg_temp.session_id('EmiLymphatic', '2027-02-26')) like 'ERR%not one of this class%', 'C16 a date of another class is refused');
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_found', 1, pg_temp.session_id('EmiLymphatic', '2027-02-26')) like 'ERR%no date to choose%', 'C17 Foundation has no date to choose: every seat attends every session');
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_skin3', 4, :'sk_mar') like 'ERR%not on a live invoice%' and pg_temp.choose('staff_a', :'l_a_skin3', 0, :'sk_mar') like 'ERR%not on a live invoice%',
  'C18 a seat beyond the quantity (4 of 3) is refused');
select pg_temp.check(pg_temp.err(format('insert into public.class_seat_dates(invoice_item_id, seat_no, session_id) values (%L, 1, %L)', :'l_a_skin4', :'sk_apr')) like '%not on a live invoice%',
  'C19 a cancelled invoice''s seat cannot be given a date even by a direct write');
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_skin4', 1, :'sk_apr') like 'ERR%not on a live invoice%', 'C19 nor through the page function');
select pg_temp.check(pg_temp.act('im', format('select public.class_choose_date(%L, 1, %L)::text', :'l_a_skin3', :'sk_mar')) like 'ERR 42501%'
   and pg_temp.refused(pg_temp.choose('former', :'l_a_skin3', 1, :'sk_mar')) and pg_temp.refused(pg_temp.choose('nobody', :'l_a_skin3', 1, :'sk_mar'))
   and pg_temp.refused(pg_temp.choose(null, :'l_a_skin3', 1, :'sk_mar')), 'C20 an Inventory Manager, a former member of staff, a signed-in non-staff and anon cannot choose a date');
select pg_temp.check(pg_temp.act('staff_a', format('insert into public.class_seat_dates(invoice_item_id, seat_no, session_id) values (%L, 2, %L)', :'l_a_skin3', :'sk_apr')) like 'ERR 42501%',
  'C21 a login cannot write class_seat_dates directly (42501)');
-- The Lymphatic Class: dates kept by Owners and Managers, no limit.
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_lc', 1, null) like '%"changed": false%', 'C22 the Lymphatic Class has no date yet: nothing to choose');
select pg_temp.act('owner', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'),
   '{"title":"In-person day","session_date":"2027-02-06","starts_at":"10:00","ends_at":"17:00","mode":"in_person","venue":"The Adelphi"}')) as lc_d1 \gset
select pg_temp.session_id('L-C', '2027-02-06') as lc_s1 \gset
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_a', :'l_a_lc', 1, :'lc_s1')) like '%"changed": true%' and pg_temp.okv(pg_temp.choose('staff_a', :'l_a_lc', 2, :'lc_s1')) like '%"changed": true%',
  'C23 the Lymphatic Class''s seats choose a day from the list the Owner keeps');
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('L-C', 8))) as a_lc2 \gset
select pg_temp.line_of(:'a_lc2', 'L-C') as l_a_lc2 \gset
select pg_temp.check((select count(*) from generate_series(1, 8) g where pg_temp.okv(pg_temp.choose('owner', :'l_a_lc2', g, :'lc_s1')) is not null) = 8
   and pg_temp.taken('owner', 'L-C', '2027-02-06') = 10, 'C24 no limit for the Lymphatic Class: 10 seats on one day');

-- ═════ A Attendance ═════
select pg_temp.check(pg_temp.okv(pg_temp.tick('staff_a', :'sk_apr', :'l_a_skin3', 1)) like '%"changed": true%', 'A1 staff tick their store''s seat on the date it chose');
select pg_temp.check(pg_temp.tick('staff_a', :'sk_mar', :'l_a_skin3', 1) like 'ERR%chose another date%', 'A2 a choose-a-date seat is ticked only on its date');
select pg_temp.check(pg_temp.tick('staff_a', :'sk_apr', :'l_a_skin3', 3) like 'ERR%chose another date%', 'A2 (a seat that chose March is not ticked on April)');
select pg_temp.check(pg_temp.refused(pg_temp.tick('staff_a', :'sk_mar', :'l_b_skin1', 1)) and pg_temp.refused(pg_temp.tick('manager', :'sk_mar', :'l_b_skin1', 1)),
  'A3 staff and the Manager of store A cannot tick a store B seat');
select pg_temp.check(pg_temp.okv(pg_temp.tick('staff_b', :'sk_mar', :'l_b_skin1', 1)) like '%"changed": true%', 'A4 staff of store B tick theirs');
select pg_temp.check(pg_temp.tick('staff_a', :'sk_apr', :'l_a_skin3', 1) like '%"changed": false%', 'A5 ticking twice changes nothing');
select pg_temp.check(pg_temp.choose('staff_a', :'l_a_skin3', 1, :'sk_mar') like 'ERR%ticked as attended%', 'A6 a date with a tick cannot be changed until the tick is removed');
select pg_temp.check(pg_temp.okv(pg_temp.tick('staff_a', :'sk_apr', :'l_a_skin3', 1, false)) like '%"changed": true%' and pg_temp.ticks(:'l_a_skin3') = 0, 'A7 a tick is removed');
select pg_temp.check((select (s->>'attended') from jsonb_array_elements(pg_temp.page('staff_b')->'seats') s where (s->>'invoice_item_id')::uuid = :'l_b_skin1'::uuid) = '["' || :'sk_mar' || '"]',
  'A8 the page shows who attended');
-- Foundation: every session.
select pg_temp.session_id('EmiLymphatic', '2027-01-29') as f1 \gset
select pg_temp.session_id('EmiLymphatic', '2027-02-26') as f2 \gset
select pg_temp.check(pg_temp.okv(pg_temp.tick('staff_a', :'f1', :'l_a_found', 1)) like '%true%' and pg_temp.okv(pg_temp.tick('staff_a', :'f2', :'l_a_found', 1)) like '%true%'
   and pg_temp.okv(pg_temp.tick('staff_a', :'f1', :'l_a_found', 2)) like '%true%' and pg_temp.ticks(:'l_a_found') = 3, 'A9 Foundation: a seat is ticked at every session it attends (seat 1 at 2, seat 2 at 1)');
select pg_temp.check(pg_temp.refused(pg_temp.tick('staff_a', :'f1', :'l_b_found', 1)), 'A10 and not for the other store''s seat');
select pg_temp.check(pg_temp.tick('staff_a', :'sk_apr', :'l_a_found', 1) like 'ERR%did not buy this class%', 'A11 a session of another class is refused');
select pg_temp.check(pg_temp.tick('staff_a', :'f1', :'l_a_found', 3) like 'ERR%not on a live invoice%', 'A12 a seat beyond the quantity is refused');
select pg_temp.refund_units(:'a_found', :'l_a_found', 1) as r13 \gset
select pg_temp.check(:'r13' = 'ok' and (select public.class_line_units(:'l_a_found'::uuid)) = 1
   and pg_temp.tick('staff_a', :'f2', :'l_a_found', 2) like 'ERR%not on a live invoice%', 'A13 a refunded seat (seat 2 of 2) cannot be ticked');
select pg_temp.cancel(:'a_found') as r14 \gset
select pg_temp.check(:'r14' = 'ok' and pg_temp.tick('staff_a', :'f2', :'l_a_found', 1) like 'ERR%not on a live invoice%'
   and pg_temp.seats_of('staff_a', 'EmiLymphatic') = pg_temp.expected('EmiLymphatic', 'storeA'), 'A14 a cancelled invoice''s seat cannot be ticked and is off the list (the other live store A seats are left)');
select pg_temp.check(pg_temp.act('im', format('select public.class_set_attendance(%L, %L, 1, true)::text', :'f1', :'l_b_found')) like 'ERR 42501%'
   and pg_temp.refused(pg_temp.tick('former', :'f1', :'l_b_found', 1)) and pg_temp.refused(pg_temp.tick(null, :'f1', :'l_b_found', 1)), 'A15 an Inventory Manager, a former member of staff and anon cannot tick');
select pg_temp.check(pg_temp.act('staff_a', format('insert into public.class_attendance(session_id, invoice_item_id, seat_no) values (%L, %L, 1)', :'f1', :'l_b_found')) like 'ERR 42501%',
  'A16 a login cannot write class_attendance directly');
select pg_temp.check(pg_temp.act('staff_a', 'select count(*)::text from public.class_attendance') like 'ok:%'
   and pg_temp.okv(pg_temp.act('staff_b', format('select count(*)::text from public.class_seat_dates where invoice_item_id = %L', :'l_a_lc'))) = '0'
   and pg_temp.okv(pg_temp.act('staff_a', format('select count(*)::text from public.class_seat_dates where invoice_item_id = %L', :'l_a_lc'))) = '2'
   and pg_temp.okv(pg_temp.act('manager', format('select count(*)::text from public.class_seat_dates where invoice_item_id = %L', :'l_a_lc'))) = '2'
   and pg_temp.okv(pg_temp.act('mgr_b', format('select count(*)::text from public.class_seat_dates where invoice_item_id = %L', :'l_a_lc'))) = '0'
   and pg_temp.okv(pg_temp.act('admin', format('select count(*)::text from public.class_seat_dates where invoice_item_id = %L', :'l_a_lc'))) = '2'
   and pg_temp.okv(pg_temp.act('im', 'select count(*)::text from public.class_seat_dates')) = '0',
  'A17 the tables'' own read rule follows the page: store B''s staff and Manager and an Inventory Manager read none of store A''s rows, store A''s staff and Manager and an Admin do');

-- ═════ E Only Owners and Managers edit dates and details ═════
select pg_temp.check(pg_temp.refused(pg_temp.act('staff_a', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Extra","session_date":"2027-03-06"}')))
   and pg_temp.refused(pg_temp.act('admin', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Extra","session_date":"2027-03-06"}')))
   and pg_temp.refused(pg_temp.act('im', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Extra","session_date":"2027-03-06"}')))
   and pg_temp.refused(pg_temp.act('former', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Extra","session_date":"2027-03-06"}')))
   and pg_temp.refused(pg_temp.act(null, format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Extra","session_date":"2027-03-06"}')))
   and not exists (select 1 from public.class_sessions where voucher_id = pg_temp.fx('v_L-C') and session_date = '2027-03-06'),
  'E1 staff, Admin, an Inventory Manager, a former member of staff and anon cannot add a date (42501); none was added');
select pg_temp.okv(pg_temp.act('manager', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'),
      '{"title":"In-person day","session_date":"2027-03-06","starts_at":"10:00","ends_at":"17:00","mode":"in_person","venue":"The Adelphi"}'))) as e2 \gset
select pg_temp.check(:'e2' <> '' and exists (select 1 from public.class_sessions where voucher_id = pg_temp.fx('v_L-C') and session_date = '2027-03-06' and seq = 2),
  'E2 a Manager adds a date to the Lymphatic Class (seq 2)');
select pg_temp.check(pg_temp.act('owner', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Again","session_date":"2027-03-06"}')) like 'ERR%already has a date on 2027-03-06%',
  'E3 the same day twice is refused in words');
select pg_temp.check(pg_temp.act('owner', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Bad","session_date":"2027-03-07","kind":"party"}')) like 'ERR%Unknown kind%'
   and pg_temp.act('owner', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Bad","session_date":"2027-03-07","starts_at":"17:00","ends_at":"10:00"}')) like 'ERR%end after it starts%'
   and pg_temp.act('owner', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'), '{"title":"Bad"}')) like 'ERR%needs its day%',
  'E4 a bad kind, a date that ends before it starts and a date without a day are refused');
select pg_temp.session_id('L-C', '2027-03-06') as lc_s2 \gset
select pg_temp.okv(pg_temp.act('manager', format('select public.class_save_session(%L, %L, %L::jsonb)::text', pg_temp.fx('v_L-C'), :'lc_s2', '{"session_date":"2027-03-13","venue":"Another room"}'))) as e5 \gset
select pg_temp.check(:'e5' <> '' and (select session_date::text || '|' || venue from public.class_sessions where id = :'lc_s2') = '2027-03-13|Another room'
   and (select title from public.class_sessions where id = :'lc_s2') = 'In-person day', 'E5 a Manager changes a date: what is not named is kept');
select pg_temp.check(pg_temp.refused(pg_temp.act('staff_a', format('select public.class_save_session(%L, %L, %L::jsonb)::text', pg_temp.fx('v_L-C'), :'lc_s2', '{"session_date":"2027-03-20"}')))
   and (select session_date::text from public.class_sessions where id = :'lc_s2') = '2027-03-13', 'E6 staff cannot change a date');
select pg_temp.check(pg_temp.act('owner', format('select public.class_save_session(%L, %L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), :'lc_s2', '{"session_date":"2027-03-20"}')) like 'ERR%does not belong to this class%',
  'E7 a date of another class is not changed through this one');
select pg_temp.check(pg_temp.refused(pg_temp.act('staff_a', format('select public.class_remove_session(%L)::text', :'lc_s2')))
   and pg_temp.refused(pg_temp.act('admin', format('select public.class_remove_session(%L)::text', :'lc_s2'))), 'E8 staff and Admin cannot remove a date');
select pg_temp.check(pg_temp.act('owner', format('select public.class_remove_session(%L)::text', :'lc_s1')) like 'ERR%stays%', 'E9 a date a seat chose cannot be removed');
select pg_temp.check(pg_temp.act('owner', format('select public.class_remove_session(%L)::text', :'f1')) like 'ERR%stays%', 'E9 nor one somebody was ticked at (Foundation session 1)');
select pg_temp.okv(pg_temp.act('owner', format('select public.class_remove_session(%L)::text', :'lc_s2'))) as e10 \gset
select pg_temp.check(:'e10' <> '' and not exists (select 1 from public.class_sessions where id = :'lc_s2'), 'E10 an unused date is removed');
select pg_temp.check((select count(*) from public.audit_logs where action in ('class_session_added', 'class_session_changed', 'class_session_removed')) >= 4
   and (select count(*) from public.audit_logs where action = 'class_date_chosen') >= 5 and (select count(*) from public.audit_logs where action = 'class_attended') >= 3,
  'E11 dates added, changed and removed, seat dates and ticks are in the Audit Log');
-- Details.
select pg_temp.check(pg_temp.refused(pg_temp.act('staff_a', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), '{"summary":"Changed"}')))
   and pg_temp.refused(pg_temp.act('admin', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), '{"summary":"Changed"}')))
   and pg_temp.refused(pg_temp.act('im', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), '{"summary":"Changed"}')))
   and (select summary from public.class_vouchers where voucher_id = pg_temp.fx('v_KPopClass')) like '1-day course%', 'E12 staff, Admin and an Inventory Manager cannot edit a class''s details');
select pg_temp.okv(pg_temp.act('manager', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), '{"summary":"Changed by a Manager"}'))) as e13 \gset
select pg_temp.check(:'e13' <> '' and (select summary from public.class_vouchers where voucher_id = pg_temp.fx('v_KPopClass')) = 'Changed by a Manager'
   and (select details->>'fee_note' from public.class_vouchers where voucher_id = pg_temp.fx('v_KPopClass')) like 'S$676%', 'E13 a Manager edits the summary; the details they did not name stay');
select pg_temp.check(pg_temp.act('owner', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), '{"capacity_per_date":3}')) like 'ERR%already has 4 seats%'
   and (select capacity_per_date from public.class_vouchers where voucher_id = pg_temp.fx('v_KPopClass')) = 6, 'E14 the capacity cannot go below what a date holds (4 on 24 Mar)');
select pg_temp.check(pg_temp.act('owner', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_EmiLymphatic'), '{"capacity_per_date":5}')) like 'ERR%whose seats choose a date%', 'E15 a workshop whose seats attend every session has no capacity per date');
select pg_temp.okv(pg_temp.act('owner', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), '{"capacity_per_date":4}'))) as e16 \gset
select pg_temp.check(:'e16' <> '' and pg_temp.choose('owner', :'l_b_skin2', 1, :'sk_mar') like 'ERR 23514%full: 4 of 4%', 'E16 a capacity of exactly what the date holds (4) is allowed, and the next seat is refused (4 of 4)');
select pg_temp.okv(pg_temp.act('owner', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), '{"capacity_per_date":6}'))) as e16b \gset
select pg_temp.check(:'e16b' <> '' and pg_temp.okv(pg_temp.choose('owner', :'l_b_skin2', 1, :'sk_mar')) is not null and pg_temp.taken('owner', 'KPopClass', '2027-03-24') = 5, 'E16b back to 6: the seat fits (5 on 24 Mar)');
select pg_temp.check(pg_temp.act('owner', format('select public.class_save_details(%L, %L::jsonb)::text', pg_temp.fx('v_KPopClass'), '{"details":"not an object"}')) like 'ERR%named entries%', 'E17 details must be an object');
select pg_temp.check(pg_temp.act('staff_a', format('update public.class_vouchers set summary = %L', 'x')) like 'ERR 42501%'
   and pg_temp.act('staff_a', format('delete from public.class_sessions where id = %L', :'f2')) like 'ERR 42501%'
   and pg_temp.act('manager', format('update public.class_sessions set session_date = %L where id = %L', '2027-02-27', :'f2')) like 'ERR 42501%',
  'E18 a login (staff or Manager) cannot write the tables directly; only the functions do');

-- ═════ L A class line corrected to another voucher, or removed (v3) ═════
insert into fx values ('v_ordinary', pg_temp.fx('ordinary'));
create function pg_temp.vlines(inv uuid, line uuid, code text) returns jsonb language sql as
$$ select jsonb_agg(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text, 'quantity', quantity,
          'voucher_id', case when id = line then pg_temp.fx('v_' || code) else voucher_id end) order by id)
     from public.invoice_items where invoice_id = inv $$;
create function pg_temp.vkeep(inv uuid, line uuid) returns jsonb language sql as
$$ select jsonb_agg(jsonb_build_object('invoice_item_id', id, 'kind', line_kind::text, 'quantity', quantity, 'voucher_id', voucher_id) order by id)
     from public.invoice_items where invoice_id = inv and id <> line $$;
-- correct_invoice as someone (the app's own call); items = the lines to keep (changed or not).
create function pg_temp.correct(inv uuid, items jsonb, who text) returns text language plpgsql as
$$begin return pg_temp.act(who, format('select public.correct_invoice(%L, %L::jsonb, %L::jsonb, %L, %L)::text', inv, items, '{}', 'Keyed wrongly', gen_random_uuid())); end$$;
create function pg_temp.entries(line uuid) returns int language plpgsql as
$$begin return (select count(*)::int from public.audit_logs where action = 'class_seats_cleared' and record_id = line); end$$;
create function pg_temp.entry(line uuid) returns public.audit_logs language plpgsql as
$$declare r public.audit_logs; begin select * into r from public.audit_logs where action = 'class_seats_cleared' and record_id = line order by created_at desc limit 1; return r; end$$;
create function pg_temp.line_seats(who text, line uuid) returns jsonb language plpgsql as
$$begin return coalesce((select jsonb_agg(s) from jsonb_array_elements(pg_temp.page(who)->'seats') s where (s->>'invoice_item_id')::uuid = line), '[]'::jsonb); end$$;
select pg_temp.session_id('KPopClass', '2027-04-28') as sk_apr2 \gset
select pg_temp.taken('owner', 'KPopClass', '2027-04-28') as t0 \gset

-- L1: a PAID skin care line (two seats, both with a date, one ticked) corrected to the Lymphatic Class by the Owner.
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 2))) as p1 \gset
select pg_temp.pay(:'p1');
select pg_temp.line_of(:'p1', 'KPopClass') as l_p1 \gset
select pg_temp.choose('staff_a', :'l_p1', 1, :'sk_apr2') like 'ok:%' as o1, pg_temp.choose('staff_a', :'l_p1', 2, :'sk_apr2') like 'ok:%' as o2 \gset
select pg_temp.tick('staff_a', :'sk_apr2', :'l_p1', 1) like 'ok:%' as o3 \gset
select pg_temp.taken('owner', 'KPopClass', '2027-04-28') as t1 \gset
select pg_temp.check(:'o1'::boolean and :'o2'::boolean and :'o3'::boolean and :'t1'::int = :'t0'::int + 2 and pg_temp.dates(:'l_p1') = 2 and pg_temp.ticks(:'l_p1') = 1,
  'L1 before: two seats chose 28 Apr, one is ticked, the date shows 2 more taken');
select pg_temp.correct(:'p1', pg_temp.vlines(:'p1', :'l_p1', 'L-C'), 'owner') as cf1 \gset
select pg_temp.taken('owner', 'KPopClass', '2027-04-28') as t2 \gset
select pg_temp.check(:'cf1' like 'ok:%' and (select voucher_id from public.invoice_items where id = :'l_p1') = pg_temp.fx('v_L-C'),
  'L1 the Owner''s correction of the paid line to the Lymphatic Class goes through');
select pg_temp.check(pg_temp.dates(:'l_p1') = 0 and pg_temp.ticks(:'l_p1') = 0 and :'t2'::int = :'t0'::int,
  'L1 its seats'' dates and ticks are gone and 28 Apr counts what it did before (taken back to ' || :'t0' || ')');
select pg_temp.check(pg_temp.entries(:'l_p1') = 1
   and (pg_temp.entry(:'l_p1')).old_data->>'voucher_id' = pg_temp.fx('v_KPopClass')::text
   and jsonb_array_length((pg_temp.entry(:'l_p1')).old_data->'seat_dates') = 2 and jsonb_array_length((pg_temp.entry(:'l_p1')).old_data->'ticks') = 1
   and (pg_temp.entry(:'l_p1')).old_data->'seat_dates'->0->>'session_id' = :'sk_apr2'
   and (pg_temp.entry(:'l_p1')).new_data->>'voucher_id' = pg_temp.fx('v_L-C')::text
   and (pg_temp.entry(:'l_p1')).module = 'classes' and (pg_temp.entry(:'l_p1')).store_id = pg_temp.fx('storeA')
   and (pg_temp.entry(:'l_p1')).reason like 'The line''s class was changed%' and (pg_temp.entry(:'l_p1')).table_name = 'invoice_items',
  'L1 one Audit Log entry: the old class, the 2 dates and the tick that went, the new class, the store');
select pg_temp.check((select bool_and((s->>'voucher_id')::uuid = pg_temp.fx('v_L-C') and s->>'session_id' is null and s->'attended' = '[]'::jsonb) and count(*) = 2
      from jsonb_array_elements(pg_temp.line_seats('owner', :'l_p1')) s),
  'L1 the page lists the 2 seats under the Lymphatic Class with no date and no tick');
select pg_temp.check(pg_temp.okv(pg_temp.choose('staff_a', :'l_p1', 1, :'lc_s1')) like '%"changed": true%', 'L1 and a Lymphatic Class day can now be chosen for them');

-- L2: an UNPAID skin care line corrected to Foundation by STAFF of the store.
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 2))) as p2 \gset
select pg_temp.line_of(:'p2', 'KPopClass') as l_p2 \gset
select pg_temp.choose('staff_a', :'l_p2', 1, :'sk_apr2') like 'ok:%' as o1, pg_temp.choose('staff_a', :'l_p2', 2, :'sk_apr2') like 'ok:%' as o2 \gset
select pg_temp.tick('staff_a', :'sk_apr2', :'l_p2', 2) like 'ok:%' as o3 \gset
select pg_temp.taken('owner', 'KPopClass', '2027-04-28') as t3 \gset
select pg_temp.check(:'o1'::boolean and :'o2'::boolean and :'o3'::boolean and :'t3'::int = :'t0'::int + 2, 'L2 before: two seats chose 28 Apr, one ticked');
select pg_temp.correct(:'p2', pg_temp.vlines(:'p2', :'l_p2', 'EmiLymphatic'), 'staff_a') as f2 \gset
select pg_temp.taken('owner', 'KPopClass', '2027-04-28') as t4 \gset
select pg_temp.check(:'f2' like 'ok:%' and (select voucher_id from public.invoice_items where id = :'l_p2') = pg_temp.fx('v_EmiLymphatic'),
  'L2 Staff of the store correct the unpaid line to Foundation');
select pg_temp.check(pg_temp.dates(:'l_p2') = 0 and pg_temp.ticks(:'l_p2') = 0 and :'t4'::int = :'t0'::int and pg_temp.entries(:'l_p2') = 1
   and jsonb_array_length((pg_temp.entry(:'l_p2')).old_data->'seat_dates') = 2 and (pg_temp.entry(:'l_p2')).old_data->'ticks'->0->>'seat_no' = '2',
  'L2 dates and ticks gone, taken back, one entry (2 dates, the tick of seat 2)');
select pg_temp.check((select bool_and((s->>'voucher_id')::uuid = pg_temp.fx('v_EmiLymphatic') and s->>'session_id' is null and s->'attended' = '[]'::jsonb) and count(*) = 2
      from jsonb_array_elements(pg_temp.line_seats('owner', :'l_p2')) s)
   and pg_temp.okv(pg_temp.tick('staff_a', pg_temp.session_id('EmiLymphatic', '2027-01-29'), :'l_p2', 1)) like '%"changed": true%',
  'L2 listed under Foundation with no date or tick, and its seats can be ticked at Foundation sessions (the repair path the page lacked)');

-- L3: an unpaid class line REMOVED through the normal edit path (correct_invoice without it).
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 1), pg_temp.vl('ordinary', 1))) as p3 \gset
select pg_temp.line_of(:'p3', 'KPopClass') as l_p3 \gset
select pg_temp.choose('staff_a', :'l_p3', 1, :'sk_apr2') like 'ok:%' as o1 \gset
select pg_temp.tick('staff_a', :'sk_apr2', :'l_p3', 1) like 'ok:%' as o2 \gset
select pg_temp.correct(:'p3', pg_temp.vkeep(:'p3', :'l_p3'), 'owner') as f3 \gset
select pg_temp.check(:'o1'::boolean and :'o2'::boolean and :'f3' like 'ok:%' and not exists (select 1 from public.invoice_items where id = :'l_p3'),
  'L3 the unpaid invoice''s class line is removed by the edit');
select pg_temp.check(pg_temp.dates(:'l_p3') = 0 and pg_temp.ticks(:'l_p3') = 0 and pg_temp.entries(:'l_p3') = 1
   and (pg_temp.entry(:'l_p3')).reason like 'The invoice line was removed%' and (pg_temp.entry(:'l_p3')).new_data->>'removed' = 'true'
   and jsonb_array_length((pg_temp.entry(:'l_p3')).old_data->'seat_dates') = 1 and jsonb_array_length((pg_temp.entry(:'l_p3')).old_data->'ticks') = 1
   and (pg_temp.entry(:'l_p3')).store_id = pg_temp.fx('storeA'),
  'L3 its date and tick went with it (the cascade) and the removal is in the Audit Log, with what went');
-- A removed class line that had nothing recorded writes nothing.
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 1), pg_temp.vl('ordinary', 1))) as p3b \gset
select pg_temp.line_of(:'p3b', 'KPopClass') as l_p3b \gset
select count(*) as n_entries0 from public.audit_logs where action = 'class_seats_cleared' \gset
select pg_temp.correct(:'p3b', pg_temp.vkeep(:'p3b', :'l_p3b'), 'owner') as f3b \gset
select pg_temp.check(:'f3b' like 'ok:%' and not exists (select 1 from public.invoice_items where id = :'l_p3b')
   and (select count(*) from public.audit_logs where action = 'class_seats_cleared') = :'n_entries0'::int, 'L3b a class line removed with nothing recorded writes no entry');

-- L4: updates that must do nothing: a non-class line's voucher_id; voucher_id left as it is on a class line with a date.
insert into public.vouchers(name, code, selling_price) values ('C548 Ordinary Two', 'C548W' || substr(md5(random()::text), 1, 5), 20) returning id as ord2 \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('ordinary', 1))) as p4 \gset
select pg_temp.line_of(:'p4', 'ordinary') as l_p4 \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 1))) as p5 \gset
select pg_temp.line_of(:'p5', 'KPopClass') as l_p5 \gset
select pg_temp.choose('staff_a', :'l_p5', 1, :'sk_apr2') like 'ok:%' as o1 \gset
select pg_temp.tick('staff_a', :'sk_apr2', :'l_p5', 1) like 'ok:%' as o2 \gset
select count(*) as n_dates0 from public.class_seat_dates \gset
select count(*) as n_entries1 from public.audit_logs where action = 'class_seats_cleared' \gset
update public.invoice_items set voucher_id = :'ord2' where id = :'l_p4';
update public.invoice_items set voucher_id = voucher_id, quantity = quantity, item_name_snapshot = item_name_snapshot where id = :'l_p5';
select pg_temp.check(:'o1'::boolean and :'o2'::boolean and (select count(*) from public.class_seat_dates) = :'n_dates0'::int and pg_temp.dates(:'l_p5') = 1 and pg_temp.ticks(:'l_p5') = 1
   and (select count(*) from public.audit_logs where action = 'class_seats_cleared') = :'n_entries1'::int,
  'L4 a voucher_id update of a non-class line, and an update that leaves a class line''s voucher_id as it is: nothing deleted, no entry');
-- ... and a direct change of a class line to a voucher that is not a class clears it, with its entry.
update public.invoice_items set voucher_id = pg_temp.fx('ordinary') where id = :'l_p5';
select pg_temp.check(pg_temp.dates(:'l_p5') = 0 and pg_temp.ticks(:'l_p5') = 0 and pg_temp.entries(:'l_p5') = 1
   and (pg_temp.entry(:'l_p5')).new_data->>'voucher_id' = pg_temp.fx('ordinary')::text,
  'L4b a direct change of a class line to a non-class voucher clears its date and tick (one entry)');

-- L5: removing a date.
select pg_temp.act('owner', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'),
   '{"title":"Day A","session_date":"2027-05-01","mode":"in_person","venue":"The Adelphi"}')) as lc_a \gset
select pg_temp.act('owner', format('select public.class_save_session(%L, null, %L::jsonb)::text', pg_temp.fx('v_L-C'),
   '{"title":"Day B","session_date":"2027-05-08","mode":"in_person","venue":"The Adelphi"}')) as lc_b \gset
select pg_temp.session_id('L-C', '2027-05-01') as s_a, pg_temp.session_id('L-C', '2027-05-08') as s_b \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('L-C', 1))) as p7 \gset
select pg_temp.line_of(:'p7', 'L-C') as l_p7 \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('L-C', 1))) as p8 \gset
select pg_temp.line_of(:'p8', 'L-C') as l_p8 \gset
select pg_temp.choose('staff_a', :'l_p7', 1, :'s_a') like 'ok:%' as o1, pg_temp.choose('staff_a', :'l_p8', 1, :'s_b') like 'ok:%' as o2 \gset
select pg_temp.check(pg_temp.act('owner', format('select public.class_remove_session(%L)::text', :'s_b')) like 'ERR%A seat chose this date or was ticked at it, so it stays%'
   and exists (select 1 from public.class_sessions where id = :'s_b'), 'L5a a date a LIVE seat chose is refused, as before');
select pg_temp.cancel(:'p7') as c7 \gset
select pg_temp.act('owner', format('select public.class_remove_session(%L)::text', :'s_a')) as rm \gset
select pg_temp.check(:'c7' = 'ok' and :'rm' like 'ok:%' and not exists (select 1 from public.class_sessions where id = :'s_a') and pg_temp.dates(:'l_p7') = 0,
  'L5b a date only a CANCELLED seat chose is removed (its date row goes with it)');
select pg_temp.check((select (a.old_data->'cleared_seat_dates'->0->>'invoice_item_id') = :'l_p7' and jsonb_array_length(a.old_data->'cleared_seat_dates') = 1
        and a.old_data->>'session_date' = '2027-05-01'
      from public.audit_logs a where a.action = 'class_session_removed' and a.record_id = :'s_a'::uuid),
  'L5c the class_session_removed entry lists the cleared seat date');
select pg_temp.check(pg_temp.act('owner', format('select public.class_remove_session(%L)::text', :'f1')) like 'ERR%Someone was ticked as attended on this date, so it stays. Change this date instead.%',
  'L5d a date anyone was ticked at is refused with its own sentence (Foundation session 1)');
select pg_temp.session_id('KPopClass', '2027-05-26') as sk_may \gset
select pg_temp.mk('storeA', 'buyerA', jsonb_build_array(pg_temp.vl('KPopClass', 1))) as p9 \gset
select pg_temp.line_of(:'p9', 'KPopClass') as l_p9 \gset
select pg_temp.choose('staff_a', :'l_p9', 1, :'sk_may') like 'ok:%' as o1 \gset
select pg_temp.tick('staff_a', :'sk_may', :'l_p9', 1) like 'ok:%' as o2 \gset
select pg_temp.cancel(:'p9') as c9 \gset
select pg_temp.check(:'c9' = 'ok' and pg_temp.act('owner', format('select public.class_remove_session(%L)::text', :'sk_may')) like 'ERR%Someone was ticked%'
   and exists (select 1 from public.class_sessions where id = :'sk_may'), 'L5e a tick of a cancelled seat still keeps the date (any tick refuses)');

-- L6: the new function and the two triggers.
select pg_temp.check(not has_function_privilege('anon', 'public.trg_class_line_changed()', 'execute')
   and not has_function_privilege('authenticated', 'public.trg_class_line_changed()', 'execute')
   and has_function_privilege('service_role', 'public.trg_class_line_changed()', 'execute')
   and (select p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig) from pg_proc p where p.oid = 'public.trg_class_line_changed()'::regprocedure),
  'L6a trg_class_line_changed: no login and no anon may call it; owner rights, search path public, pg_temp');
select pg_temp.check((select count(*) from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and t.tgname = 'class_line_voucher_changed' and t.tgenabled = 'O'
        and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER class_line_voucher_changed AFTER UPDATE OF voucher_id ON public.invoice_items FOR EACH ROW WHEN ((old.voucher_id IS DISTINCT FROM new.voucher_id)) EXECUTE FUNCTION trg_class_line_changed()') = 1
   and (select count(*) from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and t.tgname = 'class_line_removed' and t.tgenabled = 'O'
        and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER class_line_removed BEFORE DELETE ON public.invoice_items FOR EACH ROW WHEN ((old.line_kind = ''voucher''::invoice_line_kind)) EXECUTE FUNCTION trg_class_line_changed()') = 1,
  'L6b the two triggers on invoice_items are as said (after update of voucher_id when it changed; before delete of a voucher line)');
select pg_temp.check(not exists (select 1 from tg0 b where not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and t.tgname = b.tgname and pg_get_triggerdef(t.oid) = b.def))
   and (select count(*) from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and not t.tgisinternal and t.tgname like 'class\_%') = 2,
  'L6c every older trigger of invoice_items is as before, and only the two class triggers are new');

-- ═════ U Undo ═════
\if :by_us
select pg_temp.fp() as fp_548 \gset
select count(*) as n_dates_548 from public.class_seat_dates \gset
-- U1: a real undo refuses while staff recorded seat dates or ticks (there are some now); nothing changes.
savepoint u1;
\set ON_ERROR_STOP off
\ir :undo
\set ON_ERROR_STOP on
rollback to savepoint u1;
select :n_dates_548 > 0 as has_dates \gset
select pg_temp.check(:'has_dates'::boolean and pg_temp.fp() = :'fp_548' and to_regclass('public.class_seat_dates') is not null
   and (select name from public.vouchers where code = 'KPopClass' and deleted_at is null) = 'Korea No.1 Skin Care Workshop',
  'U1 a real undo refuses while staff recorded seat dates or ticks, and changes nothing');
\if :{?LAST_ERROR_MESSAGE}
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'UNDO 548: staff recorded dates or attendance%', 'U1 its sentence: ' || :'LAST_ERROR_MESSAGE');
\endif
-- U2: a test file's undo (the flag on) puts everything back exactly.
select set_config('energia.undo548_test_only', 'on', true) \g /dev/null
\ir :undo
select pg_temp.check(pg_temp.fp() = :'fp_before', 'U2 after the UNDO the functions are production''s after 549 again (fingerprint ' || :'fp_before' || ')');
select pg_temp.check(to_regclass('public.class_vouchers') is null and to_regclass('public.class_sessions') is null and to_regclass('public.class_seat_dates') is null
   and to_regclass('public.class_attendance') is null, 'U3 the four tables are gone');
select pg_temp.check((select string_agg(v.code || '=' || v.name, '; ' order by v.code) from public.vouchers v
   where v.code in ('EmiLymphatic', 'AdvancedZoom', 'KPopClass', 'L-C') and v.deleted_at is null)
   = 'AdvancedZoom=Emi Advanced Lymphatic Zoom Class; EmiLymphatic=Emi Foundation Lymphatic Zoom Class; KPopClass=K Pop Facial Class; L-C=Lymphatic Class', 'U4 the old names are back');
select pg_temp.check((select item_name_snapshot from public.invoice_items where id = :'old2_line') is null and (select item_name_snapshot from public.invoice_items where id = :'old1_line') = :'old1_snap_before',
  'U5 the line 548 froze has no printed name again; the one that had its name keeps it');
select pg_temp.check((select item_name_snapshot from public.invoice_items where id = :'oldlc1_line') is null
   and (select item_name_snapshot from public.invoice_items where id = :'oldlc2_line') = 'Lymphatic Class'
   and (select item_name_snapshot from public.invoice_items where id = :'oldem_line') = 'Emi Lymphatic Zoom Class'
   and (select item_name_snapshot from public.invoice_items where id = :'old3_line') = 'K Pop Facial Class',
  'U5b the undo takes back exactly the frozen line: the Lymphatic Class line with none, the older-name line and the skin care line are as they were');
select pg_temp.check(not exists (select 1 from pr0 b join public.vouchers v on v.code = b.code and v.deleted_at is null
     where v.selling_price <> b.selling_price
        or (select md5(coalesce(string_agg(s.store_id::text || ':' || s.selling_price::text, ',' order by s.store_id), ''))
              from public.voucher_store_prices s where s.voucher_id = v.id) <> b.sp) and (select count(*) from pr0) = 4, 'U6 prices unchanged');
select pg_temp.check(coalesce(current_setting('energia.undo548_test_only', true), '') = 'off', 'U7 the test flag is cleared again');
select pg_temp.check((select count(*) from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and not t.tgisinternal) = (select count(*) from tg0)
   and not exists (select 1 from tg0 b where not exists (select 1 from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and t.tgname = b.tgname and pg_get_triggerdef(t.oid) = b.def)),
  'U7b invoice_items has exactly the triggers it had before 548, each as before');
select pg_temp.check((select count(*) from pg_proc where pronamespace = 'public'::regnamespace and prokind = 'f') = (select count(*) from fn0)
   and not exists (select 1 from fn0 a join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as def
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') b using (fn) where a.def <> b.def),
  'U8 every function is as before 548, one by one');
-- U9: a second undo refuses.
savepoint u9;
\set ON_ERROR_STOP off
\ir :undo
\set ON_ERROR_STOP on
rollback to savepoint u9;
select pg_temp.check(pg_temp.fp() = :'fp_before' and to_regclass('public.class_vouchers') is null, 'U9 a second undo refuses and changes nothing');
\if :{?LAST_ERROR_MESSAGE}
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'UNDO 548: 548 is not in%', 'U9 its sentence: ' || :'LAST_ERROR_MESSAGE');
\endif
-- U10: 548 again makes the same.
\ir :mig
select pg_temp.check(pg_temp.fp() = :'fp_548', 'U10 548 after the undo makes the same functions again');
select pg_temp.check((select count(*) from pg_trigger t where t.tgrelid = 'public.invoice_items'::regclass and t.tgname in ('class_line_voucher_changed', 'class_line_removed')) = 2, 'U10b and the two class triggers are back');
select pg_temp.check((select count(*) from public.class_sessions) = 38 and (select count(*) from public.class_vouchers) = 4
   and (select name from public.vouchers where code = 'EmiLymphatic' and deleted_at is null) = 'Lymphatic Foundation Workshop 2027'
   and (select item_name_snapshot from public.invoice_items where id = :'old2_line') = 'Emi Foundation Lymphatic Zoom Class',
  'U10 and the same data: 38 dates, the four marked, renamed, the old line frozen again');
\endif

-- Done.
select n, msg from failed order by n;
do $$ begin
  if (select count(*) from failed) > 0 then
    raise exception '% checks failed (see FAIL above)', (select count(*) from failed);
  end if;
end $$;
rollback;
